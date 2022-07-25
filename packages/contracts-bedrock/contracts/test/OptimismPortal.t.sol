// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import { Portal_Initializer, CommonTest, NextImpl, CallerCaller } from "./CommonTest.t.sol";
import { AddressAliasHelper } from "../vendor/AddressAliasHelper.sol";
import { L2OutputOracle } from "../L1/L2OutputOracle.sol";
import { OptimismPortal } from "../L1/OptimismPortal.sol";
import { Hashing } from "../libraries/Hashing.sol";
import { Proxy } from "../universal/Proxy.sol";

contract OptimismPortal_Test is Portal_Initializer {
    function test_OptimismPortalConstructor() external {
        assertEq(op.FINALIZATION_PERIOD_SECONDS(), 7 days);
        assertEq(address(op.L2_ORACLE()), address(oracle));
        assertEq(op.l2Sender(), 0x000000000000000000000000000000000000dEaD);
    }

    function test_OptimismPortalReceiveEth() external {
        vm.expectEmit(true, true, false, true);
        emitTransactionDeposited(alice, alice, 100, 100, 100_000, false, hex"");

        // give alice money and send as an eoa
        vm.deal(alice, 2**64);
        vm.prank(alice, alice);
        (bool s, ) = address(op).call{ value: 100 }(hex"");

        assert(s);
        assertEq(address(op).balance, 100);
    }

    // Test: depositTransaction fails when contract creation has a non-zero destination address
    function test_OptimismPortalContractCreationReverts() external {
        // contract creation must have a target of address(0)
        vm.expectRevert("OptimismPortal: must send to address(0) when creating a contract");
        op.depositTransaction(address(1), 1, 0, true, hex"");
    }

    // Test: depositTransaction should emit the correct log when an EOA deposits a tx with 0 value
    function test_depositTransaction_NoValueEOA() external {
        // EOA emulation
        vm.prank(address(this), address(this));
        vm.expectEmit(true, true, false, true);
        emitTransactionDeposited(
            address(this),
            NON_ZERO_ADDRESS,
            ZERO_VALUE,
            ZERO_VALUE,
            NON_ZERO_GASLIMIT,
            false,
            NON_ZERO_DATA
        );

        op.depositTransaction(
            NON_ZERO_ADDRESS,
            ZERO_VALUE,
            NON_ZERO_GASLIMIT,
            false,
            NON_ZERO_DATA
        );
    }

    // Test: depositTransaction should emit the correct log when a contract deposits a tx with 0 value
    function test_depositTransaction_NoValueContract() external {
        vm.expectEmit(true, true, false, true);
        emitTransactionDeposited(
            AddressAliasHelper.applyL1ToL2Alias(address(this)),
            NON_ZERO_ADDRESS,
            ZERO_VALUE,
            ZERO_VALUE,
            NON_ZERO_GASLIMIT,
            false,
            NON_ZERO_DATA
        );

        op.depositTransaction(
            NON_ZERO_ADDRESS,
            ZERO_VALUE,
            NON_ZERO_GASLIMIT,
            false,
            NON_ZERO_DATA
        );
    }

    // Test: depositTransaction should emit the correct log when an EOA deposits a contract creation with 0 value
    function test_depositTransaction_createWithZeroValueForEOA() external {
        // EOA emulation
        vm.prank(address(this), address(this));

        vm.expectEmit(true, true, false, true);
        emitTransactionDeposited(
            address(this),
            ZERO_ADDRESS,
            ZERO_VALUE,
            ZERO_VALUE,
            NON_ZERO_GASLIMIT,
            true,
            NON_ZERO_DATA
        );

        op.depositTransaction(ZERO_ADDRESS, ZERO_VALUE, NON_ZERO_GASLIMIT, true, NON_ZERO_DATA);
    }

    // Test: depositTransaction should emit the correct log when a contract deposits a contract creation with 0 value
    function test_depositTransaction_createWithZeroValueForContract() external {
        vm.expectEmit(true, true, false, true);
        emitTransactionDeposited(
            AddressAliasHelper.applyL1ToL2Alias(address(this)),
            ZERO_ADDRESS,
            ZERO_VALUE,
            ZERO_VALUE,
            NON_ZERO_GASLIMIT,
            true,
            NON_ZERO_DATA
        );

        op.depositTransaction(ZERO_ADDRESS, ZERO_VALUE, NON_ZERO_GASLIMIT, true, NON_ZERO_DATA);
    }

    // Test: depositTransaction should increase its eth balance when an EOA deposits a transaction with ETH
    function test_depositTransaction_withEthValueFromEOA() external {
        // EOA emulation
        vm.prank(address(this), address(this));

        vm.expectEmit(true, true, false, true);
        emitTransactionDeposited(
            address(this),
            NON_ZERO_ADDRESS,
            NON_ZERO_VALUE,
            ZERO_VALUE,
            NON_ZERO_GASLIMIT,
            false,
            NON_ZERO_DATA
        );

        op.depositTransaction{ value: NON_ZERO_VALUE }(
            NON_ZERO_ADDRESS,
            ZERO_VALUE,
            NON_ZERO_GASLIMIT,
            false,
            NON_ZERO_DATA
        );
        assertEq(address(op).balance, NON_ZERO_VALUE);
    }

    // Test: depositTransaction should increase its eth balance when a contract deposits a transaction with ETH
    function test_depositTransaction_withEthValueFromContract() external {
        vm.expectEmit(true, true, false, true);
        emitTransactionDeposited(
            AddressAliasHelper.applyL1ToL2Alias(address(this)),
            NON_ZERO_ADDRESS,
            NON_ZERO_VALUE,
            ZERO_VALUE,
            NON_ZERO_GASLIMIT,
            false,
            NON_ZERO_DATA
        );

        op.depositTransaction{ value: NON_ZERO_VALUE }(
            NON_ZERO_ADDRESS,
            ZERO_VALUE,
            NON_ZERO_GASLIMIT,
            false,
            NON_ZERO_DATA
        );
    }

    // Test: depositTransaction should increase its eth balance when an EOA deposits a contract creation with ETH
    function test_depositTransaction_withEthValueAndEOAContractCreation() external {
        // EOA emulation
        vm.prank(address(this), address(this));

        vm.expectEmit(true, true, false, true);
        emitTransactionDeposited(
            address(this),
            ZERO_ADDRESS,
            NON_ZERO_VALUE,
            ZERO_VALUE,
            NON_ZERO_GASLIMIT,
            true,
            hex""
        );

        op.depositTransaction{ value: NON_ZERO_VALUE }(
            ZERO_ADDRESS,
            ZERO_VALUE,
            NON_ZERO_GASLIMIT,
            true,
            hex""
        );
        assertEq(address(op).balance, NON_ZERO_VALUE);
    }

    // Test: depositTransaction should increase its eth balance when a contract deposits a contract creation with ETH
    function test_depositTransaction_withEthValueAndContractContractCreation() external {
        vm.expectEmit(true, true, false, true);
        emitTransactionDeposited(
            AddressAliasHelper.applyL1ToL2Alias(address(this)),
            ZERO_ADDRESS,
            NON_ZERO_VALUE,
            ZERO_VALUE,
            NON_ZERO_GASLIMIT,
            true,
            NON_ZERO_DATA
        );

        op.depositTransaction{ value: NON_ZERO_VALUE }(
            ZERO_ADDRESS,
            ZERO_VALUE,
            NON_ZERO_GASLIMIT,
            true,
            NON_ZERO_DATA
        );
        assertEq(address(op).balance, NON_ZERO_VALUE);
    }

    // TODO: test this deeply
    // function test_verifyWithdrawal() external {}

    function test_finalizeWithdrawalTransaction_revertsOnRecentWithdrawal() external {
        Hashing.OutputRootProof memory outputRootProof = Hashing.OutputRootProof({
            version: bytes32(0),
            stateRoot: bytes32(0),
            withdrawerStorageRoot: bytes32(0),
            latestBlockhash: bytes32(0)
        });
        // Setup the Oracle to return an output with a recent timestamp
        uint256 recentTimestamp = block.timestamp - 1000;
        vm.mockCall(
            address(op.L2_ORACLE()),
            abi.encodeWithSelector(L2OutputOracle.getL2Output.selector),
            abi.encode(L2OutputOracle.OutputProposal(bytes32(uint256(1)), recentTimestamp))
        );

        vm.expectRevert("OptimismPortal: proposal is not yet finalized");
        op.finalizeWithdrawalTransaction(0, alice, alice, 0, 0, hex"", 0, outputRootProof, hex"");
    }

    function test_finalizeWithdrawalTransaction_revertsOninvalidWithdrawalProof() external {
        vm.mockCall(
            address(op.L2_ORACLE()),
            abi.encodeWithSelector(L2OutputOracle.getL2Output.selector),
            abi.encode(L2OutputOracle.OutputProposal(bytes32(uint256(1)), block.timestamp))
        );
        Hashing.OutputRootProof memory outputRootProof = Hashing.OutputRootProof({
            version: bytes32(0),
            stateRoot: bytes32(0),
            withdrawerStorageRoot: bytes32(0),
            latestBlockhash: bytes32(0)
        });

        vm.warp(
            oracle.getL2Output(oracle.latestBlockNumber()).timestamp +
                op.FINALIZATION_PERIOD_SECONDS() +
                1
        );

        vm.expectRevert("OptimismPortal: invalid output root proof");
        op.finalizeWithdrawalTransaction(0, alice, alice, 0, 0, hex"", 0, outputRootProof, hex"");
    }

    function test_simple_isBlockFinalized() external {
        vm.mockCall(
            address(op.L2_ORACLE()),
            abi.encodeWithSelector(L2OutputOracle.getL2Output.selector),
            abi.encode(L2OutputOracle.OutputProposal(bytes32(uint256(1)), startingBlockNumber))
        );

        // warp to the finalization period
        vm.warp(startingBlockNumber + op.FINALIZATION_PERIOD_SECONDS());
        assertEq(op.isBlockFinalized(startingBlockNumber), false);
        // warp past the finalization period
        vm.warp(startingBlockNumber + op.FINALIZATION_PERIOD_SECONDS() + 1);
        assertEq(op.isBlockFinalized(startingBlockNumber), true);
    }

    function test_isBlockFinalized() external {
        uint256 checkpoint = oracle.nextBlockNumber();
        vm.roll(checkpoint);
        vm.warp(oracle.computeL2Timestamp(checkpoint) + 1);
        vm.prank(oracle.proposer());
        oracle.proposeL2Output(keccak256(abi.encode(2)), checkpoint, 0, 0);

        // warp to the final second of the finalization period
        uint256 finalizationHorizon = block.timestamp + op.FINALIZATION_PERIOD_SECONDS();
        vm.warp(finalizationHorizon);
        // The checkpointed block should not be finalized until 1 second from now.
        assertEq(op.isBlockFinalized(checkpoint), false);
        // Nor should a block after it
        vm.expectRevert("L2OutputOracle: No output found for that block number.");
        assertEq(op.isBlockFinalized(checkpoint + 1), false);
        // Nor a block before it, even though the finalization period has passed, there is
        // not yet a checkpoint block on top of it for which that is true.
        assertEq(op.isBlockFinalized(checkpoint - 1), false);

        // warp past the finalization period
        vm.warp(finalizationHorizon + 1);
        // It should now be finalized.
        assertEq(op.isBlockFinalized(checkpoint), true);
        // So should the block before it.
        assertEq(op.isBlockFinalized(checkpoint - 1), true);
        // But not the block after it.
        vm.expectRevert("L2OutputOracle: No output found for that block number.");
        assertEq(op.isBlockFinalized(checkpoint + 1), false);
    }
}

contract OptimismPortal_FinalizeWithdrawal_Test is Portal_Initializer {
    // Reusable default values for a test withdrawal
    uint256 _n = 0;
    address _s = alice;
    address _t = bob;
    uint64 _v = 100;
    uint256 _g = 100_000;
    bytes _d = hex"";

    uint256 _proposedBlockNumber;
    bytes32 _stateRoot;
    bytes32 _storageRoot;
    bytes32 _outputRoot;
    bytes32 _withdrawalHash;
    bytes _withdrawalProof;
    Hashing.OutputRootProof internal _outputRootProof;

    event WithdrawalFinalized(bytes32 indexed, bool success);

    // Use a constructor to set the storage vars above, so as to minimize the number of ffi calls.
    constructor() public {
        super.setUp();
        // Get withdrawal proof data we can use for testing.
        (_stateRoot, _storageRoot, _outputRoot, _withdrawalHash, _withdrawalProof) = ffi
            .finalizeWithdrawalTransaction(_n, _s, _t, _v, _g, _d);

        // Setup a dummy output root proof for reuse.
        _outputRootProof = Hashing.OutputRootProof({
            version: bytes32(uint256(0)),
            stateRoot: _stateRoot,
            withdrawerStorageRoot: _storageRoot,
            latestBlockhash: bytes32(uint256(0))
        });
        _proposedBlockNumber = oracle.nextBlockNumber();
    }

    // Get the system into a nice ready-to-use state.
    function setUp() public override {
        // Configure the oracle to return the output root we've prepared.
        vm.warp(oracle.computeL2Timestamp(_proposedBlockNumber) + 1);
        vm.prank(oracle.proposer());
        oracle.proposeL2Output(_outputRoot, _proposedBlockNumber, 0, 0);

        // Warp beyond the finalization period for the block we've proposed.
        vm.warp(
            oracle.getL2Output(_proposedBlockNumber).timestamp +
                op.FINALIZATION_PERIOD_SECONDS() +
                1
        );
        // Fund the portal so that we can withdraw ETH.
        vm.deal(address(op), 0xFFFFFFFF);
    }

    // Test: finalizeWithdrawalTransaction succeeds and emits the WithdrawalFinalized event.
    function test_finalizeWithdrawalTransaction_succeeds() external {
        uint256 bobBalanceBefore = address(bob).balance;
        vm.expectEmit(true, true, true, true);
        emit WithdrawalFinalized(_withdrawalHash, true);
        op.finalizeWithdrawalTransaction(
            _n,
            _s,
            _t,
            _v,
            _g,
            _d,
            _proposedBlockNumber,
            _outputRootProof,
            _withdrawalProof
        );
        assert(address(bob).balance == bobBalanceBefore + 100);
    }

    // Test: finalizeWithdrawalTransaction cannot finalize a withdrawal with itself (the OptimismPortal) as the target.
    function test_finalizeWithdrawalTransaction_revertsOnSelfCall() external {
        vm.expectRevert("OptimismPortal: you cannot send messages to the portal contract");
        op.finalizeWithdrawalTransaction(
            _n,
            _s,
            address(op),
            _v,
            _g,
            _d,
            _proposedBlockNumber,
            _outputRootProof,
            _withdrawalProof
        );
    }

    // Test: finalizeWithdrawalTransaction reverts if the outputRootProof does not match the output root
    function test_finalizeWithdrawalTransaction_revertsOnInvalidOutputRootProof() external {
        // Modify the version to invalidate the withdrawal proof.
        _outputRootProof.version = bytes32(uint256(1));
        vm.expectRevert("OptimismPortal: invalid output root proof");
        op.finalizeWithdrawalTransaction(
            _n,
            _s,
            _t,
            _v,
            _g,
            _d,
            _proposedBlockNumber,
            _outputRootProof,
            _withdrawalProof
        );
    }

    // Test: finalizeWithdrawalTransaction reverts if the finalization period has not yet passed.
    function test_finalizeWithdrawalTransaction_revertsOnRecentWithdrawal() external {
        // Setup the Oracle to return an output with a recent timestamp
        uint256 recentTimestamp = block.timestamp - 1000;
        vm.mockCall(
            address(op.L2_ORACLE()),
            abi.encodeWithSelector(L2OutputOracle.getL2Output.selector),
            abi.encode(bytes32(uint256(1)), recentTimestamp)
        );

        vm.expectRevert("OptimismPortal: proposal is not yet finalized");
        op.finalizeWithdrawalTransaction(
            _n,
            _s,
            _t,
            _v,
            _g,
            _d,
            _proposedBlockNumber,
            _outputRootProof,
            _withdrawalProof
        );
    }

    // Test: finalizeWithdrawalTransaction reverts if the withdrawal has already been finalized.
    function test_finalizeWithdrawalTransaction_revertsOnReplay() external {
        vm.expectEmit(true, true, true, true);
        emit WithdrawalFinalized(_withdrawalHash, true);
        op.finalizeWithdrawalTransaction(
            _n,
            _s,
            _t,
            _v,
            _g,
            _d,
            _proposedBlockNumber,
            _outputRootProof,
            _withdrawalProof
        );
        vm.expectRevert("OptimismPortal: withdrawal has already been finalized");
        op.finalizeWithdrawalTransaction(
            _n,
            _s,
            _t,
            _v,
            _g,
            _d,
            _proposedBlockNumber,
            _outputRootProof,
            _withdrawalProof
        );
    }

    // Test: finalizeWithdrawalTransaction reverts if insufficient gas is supplied.
    function test_finalizeWithdrawalTransaction_revertsOnInsufficientGas() external {
        // This number was identified through trial and error.
        uint256 gasLimit = 150_000;
        (
            bytes32 stateRoot,
            bytes32 storageRoot,
            bytes32 outputRoot,
            bytes32 withdrawalHash,
            bytes memory withdrawalProof
        ) = ffi.finalizeWithdrawalTransaction(0, alice, bob, 100, gasLimit, hex"");
        Hashing.OutputRootProof memory outputRootProof = Hashing.OutputRootProof({
            version: bytes32(0),
            stateRoot: stateRoot,
            withdrawerStorageRoot: storageRoot,
            latestBlockhash: bytes32(0)
        });
        vm.mockCall(
            address(op.L2_ORACLE()),
            abi.encodeWithSelector(L2OutputOracle.getL2Output.selector),
            abi.encode(Hashing.hashOutputRootProof(outputRootProof), _proposedBlockNumber)
        );
        vm.expectRevert("OptimismPortal: insufficient gas to finalize withdrawal");
        op.finalizeWithdrawalTransaction{ gas: gasLimit }(
            0,
            alice,
            bob,
            100,
            gasLimit,
            hex"",
            _proposedBlockNumber,
            outputRootProof,
            withdrawalProof
        );
    }

    // Test: finalizeWithdrawalTransaction reverts if the proof is invalid due to non-existence of
    // the withdrawal.
    function test_finalizeWithdrawalTransaction_revertsOninvalidWithdrawalProof() external {
        // Submit a withdrawal not corresponding to the withdrawal hash.
        vm.expectRevert("OptimismPortal: invalid withdrawal inclusion proof");
        op.finalizeWithdrawalTransaction(
            _n,
            _s,
            _t,
            _v,
            _g,
            hex"abcd", // modify the default test values, keep the proof unchanged.
            _proposedBlockNumber,
            _outputRootProof,
            _withdrawalProof
        );
    }

    // Utility function used in the subsequent test. This is necessary to assert that the
    // reentrant call will revert.
    function callAndExpectRevert(bytes calldata data) external {
        vm.expectRevert("OptimismPortal: can only trigger one withdrawal per transaction");
        // Arguments here don't matter, as the require check is the first thing that happens.
        op.finalizeWithdrawalTransaction(0, alice, alice, 0, 0, hex"", 0, _outputRootProof, hex"");
    }

    // Test: finalizeWithdrawalTransaction reverts if a sub-call attempts to finalize another
    // withdrawal.
    function test_finalizeWithdrawalTransaction_revertsOnReentrancy() external {
        // Setup the Oracle to return an output with a finalized timestamp
        vm.warp(op.FINALIZATION_PERIOD_SECONDS() + 1000);
        uint256 finalizedTimestamp = block.timestamp - op.FINALIZATION_PERIOD_SECONDS() - 1;
        bytes memory data = abi.encodeWithSelector(this.callAndExpectRevert.selector);
        (
            bytes32 stateRoot,
            bytes32 storageRoot,
            bytes32 outputRoot,
            bytes32 withdrawalHash,
            bytes memory withdrawalProof
        ) = ffi.finalizeWithdrawalTransaction(_n, _s, address(this), 0, _g, data);
        Hashing.OutputRootProof memory outputRootProof = Hashing.OutputRootProof({
            version: bytes32(0),
            stateRoot: stateRoot,
            withdrawerStorageRoot: storageRoot,
            latestBlockhash: bytes32(0)
        });
        vm.mockCall(
            address(op.L2_ORACLE()),
            abi.encodeWithSelector(L2OutputOracle.getL2Output.selector),
            abi.encode(L2OutputOracle.OutputProposal(outputRoot, finalizedTimestamp))
        );

        op.finalizeWithdrawalTransaction(
            _n,
            _s,
            address(this),
            0,
            _g,
            data,
            _proposedBlockNumber,
            outputRootProof,
            withdrawalProof
        );
    }

    function test_finalizeWithdrawalTransaction_differential(
        address _sender,
        address _target,
        uint64 _value,
        uint8 _gasLimit,
        bytes memory _data
    ) external {
        uint256 _nonce = messagePasser.nonce();

        (
            bytes32 stateRoot,
            bytes32 storageRoot,
            bytes32 outputRoot,
            bytes32 withdrawalHash,
            bytes memory withdrawalProof
        ) = ffi.finalizeWithdrawalTransaction(
                _nonce,
                _sender,
                _target,
                _value,
                uint256(_gasLimit),
                _data
            );

        Hashing.OutputRootProof memory proof = Hashing.OutputRootProof({
            version: bytes32(uint256(0)),
            stateRoot: stateRoot,
            withdrawerStorageRoot: storageRoot,
            latestBlockhash: bytes32(uint256(0))
        });

        // Ensure the values returned from ffi are correct
        assertEq(outputRoot, Hashing.hashOutputRootProof(proof));
        assertEq(
            withdrawalHash,
            Hashing.hashWithdrawal(_nonce, _sender, _target, _value, uint64(_gasLimit), _data)
        );

        // Mock the call to the oracle
        vm.mockCall(
            address(oracle),
            abi.encodeWithSelector(oracle.getL2Output.selector),
            abi.encode(outputRoot, 0)
        );

        // Start the withdrawal, it must be initiated by the _sender and the
        // correct value must be passed along
        vm.deal(_sender, _value);
        vm.prank(_sender);
        messagePasser.initiateWithdrawal{ value: _value }(_target, uint256(_gasLimit), _data);
        // Ensure that the sentMessages is correct
        assertEq(messagePasser.sentMessages(withdrawalHash), true);

        vm.warp(op.FINALIZATION_PERIOD_SECONDS() + 1);
        op.finalizeWithdrawalTransaction{ value: _value }(
            messagePasser.nonce() - 1,
            _sender,
            _target,
            _value,
            uint64(_gasLimit),
            _data,
            100, // l2BlockNumber
            proof,
            withdrawalProof
        );
    }
}

contract OptimismPortalUpgradeable_Test is Portal_Initializer {
    Proxy internal proxy;
    uint64 initialBlockNum;

    function setUp() public override {
        super.setUp();
        initialBlockNum = uint64(block.number);
        proxy = Proxy(payable(address(op)));
    }

    function test_initValuesOnProxy() external {
        (uint128 prevBaseFee, uint64 prevBoughtGas, uint64 prevBlockNum) = OptimismPortal(
            payable(address(proxy))
        ).params();
        assertEq(prevBaseFee, opImpl.INITIAL_BASE_FEE());
        assertEq(prevBoughtGas, 0);
        assertEq(prevBlockNum, initialBlockNum);
    }

    function test_cannotInitProxy() external {
        vm.expectRevert("Initializable: contract is already initialized");
        OptimismPortal(payable(proxy)).initialize();
    }

    function test_cannotInitImpl() external {
        vm.expectRevert("Initializable: contract is already initialized");
        OptimismPortal(opImpl).initialize();
    }

    function test_upgrading() external {
        // Check an unused slot before upgrading.
        bytes32 slot21Before = vm.load(address(op), bytes32(uint256(21)));
        assertEq(bytes32(0), slot21Before);

        NextImpl nextImpl = new NextImpl();
        vm.startPrank(multisig);
        proxy.upgradeToAndCall(
            address(nextImpl),
            abi.encodeWithSelector(NextImpl.initialize.selector)
        );
        assertEq(proxy.implementation(), address(nextImpl));

        // Verify that the NextImpl contract initialized its values according as expected
        bytes32 slot21After = vm.load(address(op), bytes32(uint256(21)));
        bytes32 slot21Expected = NextImpl(address(op)).slot21Init();
        assertEq(slot21Expected, slot21After);
    }
}
