# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2025-01-12

### Added

- Initial release of ExFixsense
- Core FIX 4.4 protocol implementation
- Session management with GenServer-based architecture
- Multiple authentication strategies:
  - Standard (SSL certificate)
  - UsernamePassword (Coinbase, Binance)
  - OnBehalfOf (Cumberland Mining)
- Automatic handling of FIX protocol requirements:
  - Heartbeat monitoring
  - TestRequest/Heartbeat responses
  - SequenceReset processing
  - Logon/Logout flows
- Flexible SessionHandler behaviour for business logic
- Message builder with fluent API
- Two-phase message parser for performance optimization
- SSL/TLS connection support with client certificates
- Automatic reconnection with configurable retry
- Multiple concurrent session support
- Comprehensive documentation and examples
- Working examples for Cumberland broker:
  - Market data streaming
  - Security list requests
  - Order placement
  - Position requests
- 119 passing tests with comprehensive coverage

[1.0.0]: https://github.com/liharsw/ex_fixsense/releases/tag/v1.0.0
