# Hello World Arcium Project

This is a simple Hello World project demonstrating encrypted computation on the Solana blockchain using the Arcium framework.

## Overview

The project implements a basic encrypted addition operation where two encrypted numbers are added together using homomorphic encryption. The computation is performed securely within the Arcium Multi-Party Computation (MPC) environment.

## Features

- Encrypted addition of two 8-bit numbers
- Secure computation using Arcium's MPC framework
- Event emission with encrypted results
- Full test coverage demonstrating the functionality

## Project Structure

```
├── programs/hello_world/          # Solana program source code
├── encrypted-ixs/                 # Encrypted instruction definitions
├── tests/                         # TypeScript test files
├── Anchor.toml                    # Anchor framework configuration
├── Arcium.toml                    # Arcium framework configuration
└── package.json                   # Node.js dependencies and scripts
```

## Prerequisites

- Rust and Cargo
- Node.js (v16 or higher)
- Solana CLI tools
- Arcium CLI

## Installation

1. Install dependencies:
```bash
npm install
```

2. Build the project:
```bash
arcium build
```

## Testing

Run the test suite:
```bash
npm test
```

The test will:
1. Initialize the computation definition
2. Encrypt two numbers (1 and 2)
3. Perform the encrypted addition
4. Decrypt and verify the result equals 3

## Configuration

- Update `Anchor.toml` with your program ID after deployment
- Configure your Solana wallet path in `Anchor.toml`
- Adjust cluster settings as needed (currently set to localnet)

## Usage

The program provides two main functions:
- `init_add_together_comp_def`: Initializes the computation definition
- `add_together`: Performs encrypted addition of two numbers

The encrypted computation is handled by the Arcium framework, ensuring that the actual values remain encrypted throughout the computation process.
