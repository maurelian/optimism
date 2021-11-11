'use strict'

import { ethers } from 'ethers'
import { task } from 'hardhat/config'
import * as types from 'hardhat/internal/core/params/argumentTypes'
import { getContractFactory } from '../src/contract-defs'

import {
  getInput,
  color as c,
  getEtherscanUrl,
  printComparison,
} from '../src/validation-utils'

task('validate:chugsplash-dictator')
  // Provided by the signature Requestor
  .addParam(
    'dictator',
    'Address of the ChugSplashDictator to validate.',
    undefined,
    types.string
  )
  .addParam(
    'proxy',
    'Address of the L1ChugSplashProxy to validate.',
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
    if (!args.contractsRpcUrl) {
      throw new Error(
        c.red('RPC URL must be set in your env, or passed as an argument.')
      )
    }
    const provider = new ethers.providers.JsonRpcProvider(args.contractsRpcUrl)

    const network = await provider.getNetwork()
    console.log(
      `
Reading from the ${c.red(network.name)} network (Chain ID: ${c.red(
        '' + network.chainId
      )})`
    )
    const res = await getInput(
      c.yellow('Please confirm that this is the correct network? (Y/n)\n> ')
    )
    if (res !== 'Y') {
      throw new Error(
        c.red('User indicated that validation was run against the wrong chain')
      )
    }

    // eslint-disable-next-line @typescript-eslint/no-var-requires
    const dictatorArtifact = require('../artifacts/contracts/L1/deployment/ChugSplashDictator.sol/ChugSplashDictator.json')
    const dictatorCode = await provider.getCode(args.dictator)
    console.log(
      c.cyan(`
Now validating the Chugsplash Dictator deployment at\n${getEtherscanUrl(
        network,
        args.dictator
      )}`)
    )
    printComparison(
      'Comparing deployed ChugSplashDictator bytecode against local build artifacts',
      'Deployed ChugSplashDictator code',
      { name: 'Compiled bytecode', value: dictatorArtifact.deployedBytecode },
      { name: 'Deployed bytecode', value: dictatorCode }
    )
    // connect to the deployed ChugSplashDictator
    const dictatorContract = getContractFactory('ChugSplashDictator')
      .attach(args.dictator)
      .connect(provider)

    const finalOwner = await dictatorContract.finalOwner()
    printComparison(
      'Comparing the finalOwner address in the ChugSplashDictator to the multisig address',
      'finalOwner',
      { name: 'multisig address', value: args.multisig },
      { name: 'finalOwner', value: finalOwner }
    )

    const messengerSlotKey = await dictatorContract.messengerSlotKey()
    const messengerSlotVal = await dictatorContract.messengerSlotVal()
    const proxyMessengerSlot = await provider.getStorageAt(
      args.proxy,
      messengerSlotKey
    )
    printComparison(
      'Comparing the storage slots to be set with the current values in the proxy',
      'Storage slot 0',
      {
        name: `Value in the proxy at slot\n${messengerSlotKey}`,
        value: proxyMessengerSlot,
      },
      {
        name: `Dictator will setStorage at slot\n${messengerSlotKey}`,
        value: messengerSlotVal,
      }
    )
  })
