## RON Stablecoin

This repository contains the source code for the Decentralized Stablecoin System (RON), a project built with Solidity for the Ethereum blockchain. RON aims to create a decentralized stablecoin, pegged to the US Dollar (USD), through an algorithmic approach.

**Features:**

- Decentralized and Algorithmic: Operates entirely on the blockchain, utilizing algorithms to maintain the USD peg.
- Exogenous Collateralization: Users deposit a basket of supported cryptocurrencies as collateral to back the value of the stablecoin tokens.
- Transparency and Security: All transactions are publicly viewable on the blockchain, and smart contracts undergo rigorous testing to minimize vulnerabilities.
- This system functions on the assumption that users will actively participate in the liquidation process for the associated incentive.

**Foundry Integration:**

This project uses Foundry for development, testing, and deployment. Foundry offers a powerful and efficient toolkit for building and managing Solidity smart contracts.

**Getting Started:**

For detailed instructions on setting up Foundry and using this project, please refer to the official Foundry documentation: https://book.getfoundry.sh/.

**Contract Breakdown:**

**DecentralizedStableCoin.sol**: Defines the ERC20 token representing the stablecoin itself, named "Decentralized StableCoin" (RON).

**RONEngine.sol**: Acts as the core engine, handling various user interactions like depositing collateral, minting/burning RON, redeeming collateral, and liquidating positions
This file contains the main contract logic.

**OracleLib.sol**: provide functionalities for verifying data freshness from Chainlink oracles.

**Core Functions:**

- **`depositCollateral`:** Users can deposit supported cryptocurrencies to mint RON tokens.
- **`mintRon`:** Users can mint RON by depositing collateral, subject to health factor checks
- **`burnRon`:** Users can burn their RON tokens
- **`redeemCollateral`:** Users can redeem their deposited collateral, potentially in exchange for burning RON tokens.
- **`liquidate`:** for System Health, in critical situations, a user's position can be liquidated by another user if their collateral value falls below a minimum threshold relative to their minted RON. Liquidation involves burning RON and redeeming a portion of the collateral to maintain system stability.

**Additional Information:**

- _Health Factor Mechanism_:
  A core concept of the DSC system is the health factor. This factor represents the ratio of a user's collateral value to their minted RON. The health factor determines the minting limit for each user, incentivizing them to maintain sufficient collateral backing for their RON holdings and ultimately safeguarding the USD peg.
- _Liquidation Threshold and Bonus_:
  The system defines a liquidation threshold. If a user's health factor falls below this threshold, their position becomes susceptible to liquidation by another user. The liquidator receives a 10% bonus incentive on the redeemed collateral, creating an economic incentive to maintain system stability.
- _Minimum Health Factor_:
  A minimum health factor is enforced to prevent excessive minting of RON without adequate collateral support.
- _Price feeds_: Chainlink oracles are integrated to retrieve up-to-date exchange rates for the collateral tokens
- _test_: Basic stateful fuzz testing is implemented to enhance the robustness of the smart contracts.

**Note:** This is a basic example for learning purposes. Real-world smart contracts require much more rigorous security considerations, testing, and audits before deployment.
