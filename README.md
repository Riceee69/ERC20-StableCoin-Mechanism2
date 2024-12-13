# Alorithmic, Exogenous Stablecoin Pegged to the US Dollar

## Overview
Decentralized, exogenous stablecoin pegged to the US Dollar. Designed with security and stability in mind, it employs overcollateralization and robust mechanisms to ensure price stability and user protection.

---

## Key Features

### Overcollateralization
- **Collateral Ratio**: The stablecoin is 200% overcollateralized.
- **Minting Requirement**: To mint DSC (Dollar Stablecoin), users must deposit collateral worth twice the amount of DSC they wish to mint.

### Health Factor and Liquidation
- **Health Factor**: User positions are monitored for a Health Factor, which ensures the collateral is sufficient. Minimum Health Factor ratio 1
- **Liquidation Incentives**: If a user's Health Factor falls below the acceptable threshold, other users can liquidate their position. Liquidators are incentivized for performing this action.

### Price Stability Mechanisms
- **Oracle Price Feed**: Stale price and sanity checks are implemented to validate the Oracle price feed, ensuring reliable price data.
- **Freeze Mechanism**: A system is provided to freeze critical functions during abnormal price fluctuations to protect the protocol. (This feature is currently commented out.)

---

## Security and Stability
Arithmetic employs multiple layers of checks and mechanisms to maintain the stability and integrity of the stablecoin:
1. **Overcollateralization** ensures that the system remains solvent.
2. **Liquidation Mechanism** incentivizes the community to maintain healthy positions.
3. **Oracle Sanity Checks** ensure accurate pricing data.
4. **Freeze System** acts as a safeguard against extreme price volatility.

---

## Contributing
Contributions to improve and extend the Arithmetic protocol are welcome. Please follow standard contribution guidelines and submit your proposals via GitHub.

---

## License
This project is open-source and licensed under the [MIT License](LICENSE).
