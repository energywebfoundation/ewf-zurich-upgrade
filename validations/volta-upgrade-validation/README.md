## Running Tests

To run the `shadowForkValidation.js` tests using Hardhat:

1. Install dependencies:
   ```bash
   npm install
   ```

2. Set up the environment variables:
   - Copy `.env_example` to `.env`:
     ```bash
     cp .env_example .env
     ```
   - Update the `.env` file with the appropriate values for your setup.

3. Run the tests:
   ```bash
   npx hardhat test --network shadowfork
   ```

   Replace `shadowfork` with `shadowforkOE` or `shadowforkNM` if you want to target specific shadow fork networks.