'use strict'

import { ethers } from 'ethers'
import { task } from 'hardhat/config'
import * as types from 'hardhat/internal/core/params/argumentTypes'
import { hexStringEquals } from '@eth-optimism/core-utils'
import { getContractFactory } from '../src/contract-defs'

import { getInput, color as c } from '../src/task-utils'

const printComparison = (
  action: string,
  description: string,
  value1: string,
  value2: string
) => {
  console.log(action + ':')
  if (hexStringEquals(value1, value2)) {
    console.log(c.green(`${description} looks good! 😎`))
  } else {
    throw new Error(`${description} looks wrong`)
  }
  console.log() // Add some whitespace
}

task('validate:address-dictator')
  // Provided by the signature Requestor
  .addParam(
    'dictator',
    'Address of the AddressDictator to validate.',
    undefined,
    types.string
  )
  .addParam(
    'manager',
    'Address of the Address Manager contract which would be updated by the Dictator.',
    undefined,
    types.string
  )
  // Provided by the signers themselves.
  .addParam(
    'multisig',
    'Address of the multisig contract which should be the final owner',
    undefined,
    types.string
  )
  .addOptionalParam(
    'contractsRpcUrl',
    'RPC Endpoint to query for data',
    process.env.CONTRACTS_RPC_URL,
    types.string
  )
  .setAction(async (args) => {
    if (!process.env.CONTRACTS_RPC_URL) {
      throw new Error(c.red('CONTRACTS_RPC_URL not set in your env.'))
    }
    const provider = new ethers.providers.JsonRpcProvider(args.contractsRpcUrl)

    const network = await provider.getNetwork()
    console.log(
      `
Validating the deployment on the chain with:
Name: ${network.name}
Chain ID: ${network.chainId}`
    )
    const res = await getInput(c.yellow('Does that look right? (LGTM/n)\n> '))
    if (res !== 'LGTM') {
      throw new Error(
        c.red('User indicated that validation was run against the wrong chain')
      )
    }

    // eslint-disable-next-line @typescript-eslint/no-var-requires
    const dictatorArtifact = require('../artifacts/contracts/L1/deployment/AddressDictator.sol/AddressDictator.json')
    const dictatorCode = await provider.getCode(args.dictator)
    printComparison(
      'Verifying AddressDictator source code against local build artifacts',
      'Deployed AddressDictator code',
      dictatorArtifact.deployedBytecode,
      dictatorCode
    )

    // connect to the deployed AddressDictator
    const dictatorContract = getContractFactory('AddressDictator')
      .attach(args.dictator)
      .connect(provider)

    const finalOwner = await dictatorContract.finalOwner()
    printComparison(
      'Validating that finalOwner address in the AddressDictator matches multisig address',
      'finalOwner',
      finalOwner,
      args.multisig
    )

    const manager = await dictatorContract.manager()
    printComparison(
      'Validating the AddressManager address in the AddressDictator',
      'addressManager',
      manager,
      args.manager
    )

    // Get names and addresses from the Dictator.
    const namedAddresses = await dictatorContract.getNamedAddresses()

    // Connect to the deployed AddressManager so we can see which are changed or unchanged.
    const managerContract = getContractFactory('Lib_AddressManager')
      .attach(args.manager)
      .connect(provider)

    // Loop over those and compare the addresses/deployedBytecode to deployment artifacts.
    for (const pair of namedAddresses) {
      // Check for addresses that will not be changed:
      const currentAddress = await managerContract.getAddress(pair.name)
      const addressChanged = !hexStringEquals(currentAddress, pair.addr)
      if (addressChanged) {
        console.log(`${pair.name} address will be updated.`)
        console.log(`Before ${currentAddress}`)
        console.log(`After ${pair.addr}`)

        const locations = {
          ChainStorageContainer_CTC_batches:
            'L1/rollup/ChainStorageContainer.sol/ChainStorageContainer.json',
          ChainStorageContainer_SCC_batches:
            'L1/rollup/ChainStorageContainer.sol/ChainStorageContainer.json',
          CanonicalTransactionChain:
            'L1/rollup/CanonicalTransactionChain.sol/CanonicalTransactionChain.json',
          StateCommitmentChain:
            'L1/rollup/StateCommitmentChain.sol/StateCommitmentChain.json',
          BondManager: 'L1/verification/BondManager.sol/BondManager.json',
          OVM_L1CrossDomainMessenger:
            'L1/messaging/L1CrossDomainMessenger.sol/L1CrossDomainMessenger.json',
          Proxy__OVM_L1CrossDomainMessenger:
            'libraries/resolver/Lib_ResolvedDelegateProxy.sol/Lib_ResolvedDelegateProxy.json',
          Proxy__OVM_L1StandardBridge:
            './chugsplash/L1ChugSplashProxy.sol/L1ChugSplashProxy.json',
        }
        // eslint-disable-next-line @typescript-eslint/no-var-requires
        const artifact = require(`../artifacts/contracts/${
          locations[pair.name]
        }`)
        const code = await provider.getCode(pair.addr)
        printComparison(
          `Verifying ${pair.name} source code against local deployment artifacts`,
          `Deployed ${pair.name} code`,
          artifact.deployedBytecode,
          code
        )
      } else {
        console.log(`${pair.name} not updated`)
      }
    }
  })
