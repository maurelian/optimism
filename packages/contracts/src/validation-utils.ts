import { ethers } from 'ethers'
import { createInterface } from 'readline'
import { hexStringEquals } from '@eth-optimism/core-utils'
import { getContractFactory } from '../src/contract-defs'
import { names } from '../src/address-names'

export const getInput = (query) => {
  const rl = createInterface({
    input: process.stdin,
    output: process.stdout,
  })

  return new Promise((resolve) =>
    rl.question(query, (ans) => {
      rl.close()
      resolve(ans)
    })
  )
}

const codes = {
  reset: '\x1b[0m',
  red: '\x1b[0;31m',
  green: '\x1b[0;32m',
  cyan: '\x1b[0;36m',
  yellow: '\x1b[1;33m',
}

export const color = Object.fromEntries(
  Object.entries(codes).map(([k]) => [
    k,
    (msg: string) => `${codes[k]}${msg}${codes.reset}`,
  ])
)

// helper for finding the right artifact from the deployed name
const location = (name: string) => {
  return {
    'ChainStorageContainer-CTC-batches':
      'L1/rollup/ChainStorageContainer.sol/ChainStorageContainer.json',
    'ChainStorageContainer-SCC-batches':
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
      'chugsplash/L1ChugSplashProxy.sol/L1ChugSplashProxy.json',
  }[name]
}

export const getArtifact = (name: string) => {
  // eslint-disable-next-line @typescript-eslint/no-var-requires
  return require(`../artifacts/contracts/${location(name)}`)
}

export const checkDeployedConfig = async (
  provider,
  pair: { name: string; addr: string }
) => {
  logSectionHead(`
Ensure that the ${pair.name} is configured correctly`)
  if (pair.name === names.managed.contracts.StateCommitmentChain) {
    const scc = getContractFactory(pair.name)
      .attach(pair.addr)
      .connect(provider)
    //  --scc-fraud-proof-window 604800 \
    const fraudProofWindow = await scc.FRAUD_PROOF_WINDOW()
    printComparison(
      'Checking the fraudProofWindow of the StateCommitmentChain',
      'StateCommitmentChain.fraudProofWindow',
      {
        name: 'Configured fraudProofWindow',
        value: ethers.BigNumber.from(604_800).toHexString(),
      },
      {
        name: 'deployed fraudProofWindow',
        value: ethers.BigNumber.from(fraudProofWindow).toHexString(),
      }
    )
    await getInput(color.yellow('OK? Hit enter to continue.'))

    //  --scc-sequencer-publish-window 12592000 \
    const sequencerPublishWindow = await scc.SEQUENCER_PUBLISH_WINDOW()
    printComparison(
      'Checking the sequencerPublishWindow of the StateCommitmentChain',
      'StateCommitmentChain.sequencerPublishWindow',
      {
        name: 'Configured sequencerPublishWindow',
        value: ethers.BigNumber.from(604_800).toHexString(),
      },
      {
        name: 'deployed sequencerPublishWindow',
        value: ethers.BigNumber.from(sequencerPublishWindow).toHexString(),
      }
    )
    await getInput(color.yellow('OK? Hit enter to continue.'))
  } else if (pair.name === names.managed.contracts.CanonicalTransactionChain) {
    const ctc = getContractFactory(pair.name)
      .attach(pair.addr)
      .connect(provider)

    //  --ctc-max-transaction-gas-limit 15000000 \
    const maxTransactionGasLimit = await ctc.maxTransactionGasLimit()
    printComparison(
      'Checking the maxTransactionGasLimit of the CanonicalTransactionChain',
      'CanonicalTransactionChain.maxTransactionGasLimit',
      {
        name: 'Configured maxTransactionGasLimit',
        value: ethers.BigNumber.from(15_000_000).toHexString(),
      },
      {
        name: 'deployed maxTransactionGasLimit',
        value: ethers.BigNumber.from(maxTransactionGasLimit).toHexString(),
      }
    )
    await getInput(color.yellow('OK? Hit enter to continue.'))
    //  --ctc-l2-gas-discount-divisor 32 \
    const l2GasDiscountDivisor = await ctc.l2GasDiscountDivisor()
    printComparison(
      'Checking the l2GasDiscountDivisor of the CanonicalTransactionChain',
      'CanonicalTransactionChain.l2GasDiscountDivisor',
      {
        name: 'Configured l2GasDiscountDivisor',
        value: ethers.BigNumber.from(32).toHexString(),
      },
      {
        name: 'deployed l2GasDiscountDivisor',
        value: ethers.BigNumber.from(l2GasDiscountDivisor).toHexString(),
      }
    )
    await getInput(color.yellow('OK? Hit enter to continue.'))
    //  --ctc-enqueue-gas-cost 60000 \
    const enqueueGasCost = await ctc.enqueueGasCost()
    printComparison(
      'Checking the enqueueGasCost of the CanonicalTransactionChain',
      'CanonicalTransactionChain.enqueueGasCost',
      {
        name: 'Configured enqueueGasCost',
        value: ethers.BigNumber.from(60000).toHexString(),
      },
      {
        name: 'Deployed enqueueGasCost',
        value: ethers.BigNumber.from(enqueueGasCost).toHexString(),
      }
    )
    await getInput(color.yellow('OK? Hit enter to continue.'))
  } else {
    console.log(color.green(`${pair.name} has no config to check`))
    await getInput(color.yellow('\nOK? Hit enter to continue.'))
  }
}

export const getEtherscanUrl = (network, address: string) => {
  const escPrefix = network.chainId !== 1 ? `${network.name}.` : ''
  return `https://${escPrefix}etherscan.io/address/${address}`
}

// Reduces a byte string to first 32 bytes, with a '...' to indicate when it was shortened
const truncateLongString = (value: string): string => {
  return value.length > 66 ? `${value.slice(0, 66)}...` : value
}

export const printComparison = (
  action: string,
  description: string,
  expected: { name: string; value: any },
  deployed: { name: string; value: any }
) => {
  console.log(action + ':')
  if (hexStringEquals(expected.value, deployed.value)) {
    console.log(
      color.green(
        `${expected.name}: ${truncateLongString(expected.value)}
      matches
${deployed.name}: ${truncateLongString(deployed.value)}`
      )
    )
    console.log(color.green(`${description} looks good! 😎`))
  } else {
    throw new Error(`${description} looks wrong.
    ${expected.value}\ndoes not match\n${deployed.value}.
    `)
  }
  console.log() // Add some whitespace
}

export const logSectionHead = (msg: string) => {
  console.log()
  console.log(color.cyan(msg))
}
