# Solidity API

## InvalidInitializerUsed

```solidity
error InvalidInitializerUsed()
```

## BridgeWithSwap

### SwapInfo

```solidity
struct SwapInfo {
  address tokenToSend;
  address tokenToReceive;
  uint256 amountToSend;
  uint256 minAmountToReceive;
  uint256 deadline;
}
```

### swapRouter

```solidity
address swapRouter
```

### swapInfo

```solidity
mapping(uint256 => struct BridgeWithSwap.SwapInfo) swapInfo
```

Mapping of nonce to swap info

### SendWithSwap

```solidity
event SendWithSwap(address tokenToSend, address tokenToReceive, address to, uint256 amountToSend, uint256 minAmountToReceive, uint256 deadline, uint256 nonce)
```

### onlySupportedTokens

```solidity
modifier onlySupportedTokens(address token, address tokenToReceive)
```

### initialize

```solidity
function initialize(uint8[], address, uint256, address[], address, uint256) public
```

### initialize

```solidity
function initialize(uint8[] _supportedChains, address _wrappedNative, uint256 _minAmountForNative, address[] _otherChainsTokenForNative, address _relayer, uint256 _minTimeToWaitBeforeRefund, address _swapRouter) public
```

### sendWithSwap

```solidity
function sendWithSwap(address tokenToSend, address tokenToReceive, address to, uint8 dstChainId, uint256 amountToSend, uint256 minAmountToReceive, uint256 deadline) external payable
```

### withdrawWithSwap

```solidity
function withdrawWithSwap(address tokenSent, address tokenToReceive, address to, uint256 amountSent, uint256 minAmountToReceive, uint8 fromChainId, uint256 nonceOnOtherChain) external
```

