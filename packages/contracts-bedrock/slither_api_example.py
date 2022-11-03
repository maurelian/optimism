from slither import Slither
from slither.core.cfg.node import NodeType
from slither.slithir.operations import Binary, BinaryType, Condition, SolidityCall, TypeConversion

from slither.core.variables.local_variable import LocalVariable
from slither.slithir.variables import Constant


def print_echidna_property_tests(slither: Slither):
    """
    Prints the names of every fuzz test method name alongside the contract they exist within.
    :param slither: The analyzer to use for inspection.
    :return: None
    """
    # Define a list of fuzz contracts we discovered
    echidna_test_contracts = set()

    # Loop through all the contracts and find ones which have functions starting with
    # "echidna_", which do not take any arguments, and return a boolean.
    print("Echidna property tests:")
    for contract in slither.contracts:
        # Echidna will only deploy contracts without constructor arguments by default, so
        # we skip any which do not meet that criteria.
        # Note: the docstrings here mention that `signature` is a Tuple where the second
        # item is the input argument types.
        if contract.constructor is not None and len(contract.constructor.signature[1]) > 0:
            continue

        # Loop for all functions in the contract and look for an echidna property test method.
        for function in contract.functions:
            if not function.name.startswith("echidna_"):
                continue
            if not function.view and not function.pure:
                continue
            if function.visibility != "public":
                continue
            # This contract has echidna property tests. If we haven't printed anything
            # for this contract yet, we print some header information
            if contract not in echidna_test_contracts:
                # We print information about what this contract inherits from.
                # Note: `immediate_inheritance` just contains the first level of inheritance,
                # whereas `inheritance` contains all contracts this inherits from at all
                # depth levels.
                inherited_str = ", ".join([c.name for c in contract.immediate_inheritance])
                print("\nContract: {} (inherits from: {})".format(contract.name, inherited_str or "<none>"))

                # Print the heading for the property test methods in this contract to follow.
                print("Property Tests:")
                echidna_test_contracts.add(contract)

            # Print information about this method.
            print("\t-{}.{}".format(contract.name, function.full_name))
    print("")


def test_deposit_transaction_integrity(slither: Slither):
    """
    Tests that no new high-level calls were added within OptimismPortal.depositTransaction(...)
    and whether there is still an if-statement checking _isCreation which only contains a require
    statement checking _to against the zero address. Raises an error if either is false.

    Note: This is a proof of concept that can be used to ensure some methods never violate some
    properties. This same result can be achieved with less lines of code by simply checking
    the expressions of nodes or obtaining them as strings, but we check everything granularly here
    to get an idea of how to navigate individual nodes and their intermediate representation (IR).
    In practice, this can be used for much more powerful analysis. Check out slither's detectors for
    more examples: https://github.com/crytic/slither/tree/master/slither/detectors

    :param slither: The analyzer to use for inspection.
    :return: None
    """
    print("Running OptimismPortal.depositTransaction() test...")
    # Get the OptimismPortal contract (if there are multiple matches, we take the first)
    discovered_contracts = slither.get_contract_from_name("OptimismPortal")
    if discovered_contracts is None or len(discovered_contracts) < 1:
        raise LookupError("Could not find OptimismPortal contract")
    portal = discovered_contracts[0]

    # Obtain the depositTransaction function. If we fail to discover it
    deposit_function = next((f for f in portal.functions if f.name == "depositTransaction"), None,)
    if deposit_function is None:
        raise LookupError("Could not find OptimismPortal.depositTransaction function")

    # Obtain all function calls by contract_name.function_name and ensure it is as we expected.
    # Note: We could use a set here, but we check for the specific amount of calls instead, so even
    # calling a previously called method another time violates our test.
    high_level_calls = ["{}.{}".format(c.name, f.name) for c, f in deposit_function.high_level_calls]
    if sorted(high_level_calls) != sorted(["AddressAliasHelper.applyL1ToL2Alias"]):
        raise ValueError("OptimismPortal.depositTransaction has had a new high level call added.")

    # Loop through all nodes to verify an if statement on _isCreation still enforces require statement
    # against a zero-address.
    found_creation_check = False
    for node in deposit_function.nodes:
        if node.type == NodeType.IF:
            # If we found an IF statement, we check the internal representation for the condition.
            # The first IR for an IF statement should always be a condition.
            if node.irs is None or len(node.irs) == 0:
                continue
            condition_ir = node.irs[0]
            if not isinstance(condition_ir, Condition):
                continue

            # Verify the condition's value comes from a local variable
            condition_value = condition_ir.value
            if not isinstance(condition_value, LocalVariable):
                continue

            # Verify the local variable is called _isCreation
            if condition_value.name != "_isCreation":
                continue

            # Now that we verified we found an IF statement that checks a variable _isCreation,
            # lets verify it contains a require statement that compares against address(0).
            condition_value = condition_value

            # Verify the if statement only has two parts, the require + the end-if
            if len(node.sons) != 2:
                continue

            # Verify the last child node is an END-IF statement
            if node.sons[-1].type != NodeType.ENDIF:
                continue

            # Verify the first child node is an expression
            if node.sons[0].type != NodeType.EXPRESSION:
                continue
            require_expression_node = node.sons[0]

            # Verify we have three IRs for this node
            if len(require_expression_node.irs) != 3:
                continue

            # Verify the first is a type conversion from 0 to an address.
            type_conversion_ir = require_expression_node.irs[0]
            if not isinstance(type_conversion_ir, TypeConversion):
                continue
            type_conversion_constant = type_conversion_ir.variable
            if not isinstance(type_conversion_constant, Constant):
                continue

            # Verify the constant has a value of 0 and it's being converted to an address.
            if type_conversion_constant.value != 0 or type_conversion_ir.type.name != "address":
                continue

            # Verify the second IR is a binary operation (==) between our temp variable holding our converted type
            # from the previous node, and _to.
            binary_ir = require_expression_node.irs[1]
            if not isinstance(binary_ir, Binary) or binary_ir.type != BinaryType.EQUAL:
                continue

            # Verify the RHS is our address(0) temporary variable
            if binary_ir.variable_right != type_conversion_ir.lvalue:
                continue
            # Verify the LHS is a local variable named _to
            local_variable = binary_ir.variable_left
            if not isinstance(local_variable, LocalVariable) or local_variable.name != "_to":
                continue

            # Verify the last IR for this node is a SolidityCall to require(...) with two arguments
            solidity_call_ir = require_expression_node.irs[2]
            if not isinstance(solidity_call_ir, SolidityCall):
                continue
            if solidity_call_ir.function.full_name != "require(bool,string)" or len(solidity_call_ir.arguments) < 1:
                continue

            # Verify the first argument of our require statement is the return value of our binary comparison.
            if solidity_call_ir.arguments[0] != binary_ir.lvalue:
                continue

            found_creation_check = True

    # Raise an exception if we did not find our _isCreation check.
    if not found_creation_check:
        raise LookupError("Could not find the _isCreation if-statement + require check in "
                          "OptimismPortal.depositTransaction")
    else:
        print("Test passed")


if __name__ == "__main__":
    # Analyze the codebase (building the contracts using crytic-compile from the current directory)
    s = Slither(".")

    # Discover any echidna property tests and print information about the contracts.
    print_echidna_property_tests(s)

    # Test changes possibly made to OptimismPortal.depositTransaction(...)
    test_deposit_transaction_integrity(s)

