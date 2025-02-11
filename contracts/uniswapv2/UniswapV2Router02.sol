// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.7.6;

import "./libraries/UniswapV2Library.sol";
import "./libraries/SafeMath.sol";
import "./libraries/TransferHelper.sol";
import "./interfaces/IUniswapV2Router02.sol";
import "./interfaces/IUniswapV2Factory.sol";
import "./interfaces/IERC20.sol";
import "./interfaces/IWETH.sol";
import "hardhat/console.sol";

contract UniswapV2Router02 is IUniswapV2Router02 {
  using SafeMathUniswap for uint256;

  address _factory;
  address _WETH;

  function factory() external view override returns (address) {
    return _factory;
  }

  function WETH() external view override returns (address) {
    return _WETH;
  }

  modifier ensure(uint256 deadline) {
    require(deadline >= block.timestamp, "UniswapV2Router: EXPIRED");
    _;
  }

  constructor(address factory_, address WETH_) {
    _factory = factory_;
    _WETH = WETH_;
  }

  receive() external payable {
    assert(msg.sender == _WETH); // only accept ETH via fallback from the WETH contract
  }

  // **** ADD LIQUIDITY ****
  function _addLiquidity(
    address tokenA,
    address tokenB,
    uint256 amountADesired,
    uint256 amountBDesired,
    uint256 amountAMin,
    uint256 amountBMin
  ) internal virtual returns (uint256 amountA, uint256 amountB) {
    // create the pair if it doesn't exist yet
    if (IUniswapV2Factory(_factory).getPair(tokenA, tokenB) == address(0)) {
      IUniswapV2Factory(_factory).createPair(tokenA, tokenB);
    }
    (uint256 reserveA, uint256 reserveB) = UniswapV2Library.getReserves(_factory, tokenA, tokenB);
    if (reserveA == 0 && reserveB == 0) {
      (amountA, amountB) = (amountADesired, amountBDesired);
    } else {
      uint256 amountBOptimal = UniswapV2Library.quote(amountADesired, reserveA, reserveB);
      if (amountBOptimal <= amountBDesired) {
        require(amountBOptimal >= amountBMin, "UniswapV2Router: INSUFFICIENT_B_AMOUNT");
        (amountA, amountB) = (amountADesired, amountBOptimal);
      } else {
        uint256 amountAOptimal = UniswapV2Library.quote(amountBDesired, reserveB, reserveA);
        assert(amountAOptimal <= amountADesired);
        require(amountAOptimal >= amountAMin, "UniswapV2Router: INSUFFICIENT_A_AMOUNT");
        (amountA, amountB) = (amountAOptimal, amountBDesired);
      }
    }
  }

  function addLiquidity(
    address tokenA,
    address tokenB,
    uint256 amountADesired,
    uint256 amountBDesired,
    uint256 amountAMin,
    uint256 amountBMin,
    address to,
    uint256 deadline
  )
    external
    virtual
    override
    ensure(deadline)
    returns (
      uint256 amountA,
      uint256 amountB,
      uint256 liquidity
    )
  {
    (amountA, amountB) = _addLiquidity(tokenA, tokenB, amountADesired, amountBDesired, amountAMin, amountBMin);
    address pair = UniswapV2Library.pairFor(_factory, tokenA, tokenB);
    TransferHelper.safeTransferFrom(tokenA, msg.sender, pair, amountA);
    TransferHelper.safeTransferFrom(tokenB, msg.sender, pair, amountB);
    liquidity = IUniswapV2Pair(pair).mint(to);
  }

  function addLiquidityETH(
    address token,
    uint256 amountTokenDesired,
    uint256 amountTokenMin,
    uint256 amountETHMin,
    address to,
    uint256 deadline
  )
    external
    payable
    virtual
    override
    ensure(deadline)
    returns (
      uint256 amountToken,
      uint256 amountETH,
      uint256 liquidity
    )
  {
    (amountToken, amountETH) = _addLiquidity(token, _WETH, amountTokenDesired, msg.value, amountTokenMin, amountETHMin);
    address pair = UniswapV2Library.pairFor(_factory, token, _WETH);
    TransferHelper.safeTransferFrom(token, msg.sender, pair, amountToken);
    IWETH(_WETH).deposit{value: amountETH}();
    assert(IWETH(_WETH).transfer(pair, amountETH));
    liquidity = IUniswapV2Pair(pair).mint(to);
    // refund dust eth, if any
    if (msg.value > amountETH) TransferHelper.safeTransferETH(msg.sender, msg.value - amountETH);
  }

  // **** REMOVE LIQUIDITY ****
  function removeLiquidity(
    address tokenA,
    address tokenB,
    uint256 liquidity,
    uint256 amountAMin,
    uint256 amountBMin,
    address to,
    uint256 deadline
  ) public virtual override ensure(deadline) returns (uint256 amountA, uint256 amountB) {
    address pair = UniswapV2Library.pairFor(_factory, tokenA, tokenB);
    IUniswapV2Pair(pair).transferFrom(msg.sender, pair, liquidity); // send liquidity to pair
    (uint256 amount0, uint256 amount1) = IUniswapV2Pair(pair).burn(to);
    (address token0, ) = UniswapV2Library.sortTokens(tokenA, tokenB);
    (amountA, amountB) = tokenA == token0 ? (amount0, amount1) : (amount1, amount0);
    require(amountA >= amountAMin, "UniswapV2Router: INSUFFICIENT_A_AMOUNT");
    require(amountB >= amountBMin, "UniswapV2Router: INSUFFICIENT_B_AMOUNT");
  }

  function removeLiquidityETH(
    address token,
    uint256 liquidity,
    uint256 amountTokenMin,
    uint256 amountETHMin,
    address to,
    uint256 deadline
  ) public virtual override ensure(deadline) returns (uint256 amountToken, uint256 amountETH) {
    (amountToken, amountETH) = removeLiquidity(token, _WETH, liquidity, amountTokenMin, amountETHMin, address(this), deadline);
    TransferHelper.safeTransfer(token, to, amountToken);
    IWETH(_WETH).withdraw(amountETH);
    TransferHelper.safeTransferETH(to, amountETH);
  }

  function removeLiquidityWithPermit(
    address tokenA,
    address tokenB,
    uint256 liquidity,
    uint256 amountAMin,
    uint256 amountBMin,
    address to,
    uint256 deadline,
    bool approveMax,
    uint8 v,
    bytes32 r,
    bytes32 s
  ) external virtual override returns (uint256 amountA, uint256 amountB) {
    address pair = UniswapV2Library.pairFor(_factory, tokenA, tokenB);
    uint256 value = approveMax ? uint256(-1) : liquidity;
    IUniswapV2Pair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
    (amountA, amountB) = removeLiquidity(tokenA, tokenB, liquidity, amountAMin, amountBMin, to, deadline);
  }

  function removeLiquidityETHWithPermit(
    address token,
    uint256 liquidity,
    uint256 amountTokenMin,
    uint256 amountETHMin,
    address to,
    uint256 deadline,
    bool approveMax,
    uint8 v,
    bytes32 r,
    bytes32 s
  ) external virtual override returns (uint256 amountToken, uint256 amountETH) {
    address pair = UniswapV2Library.pairFor(_factory, token, _WETH);
    uint256 value = approveMax ? uint256(-1) : liquidity;
    IUniswapV2Pair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
    (amountToken, amountETH) = removeLiquidityETH(token, liquidity, amountTokenMin, amountETHMin, to, deadline);
  }

  // **** REMOVE LIQUIDITY (supporting fee-on-transfer tokens) ****
  function removeLiquidityETHSupportingFeeOnTransferTokens(
    address token,
    uint256 liquidity,
    uint256 amountTokenMin,
    uint256 amountETHMin,
    address to,
    uint256 deadline
  ) public virtual override ensure(deadline) returns (uint256 amountETH) {
    (, amountETH) = removeLiquidity(token, _WETH, liquidity, amountTokenMin, amountETHMin, address(this), deadline);
    TransferHelper.safeTransfer(token, to, IERC20Uniswap(token).balanceOf(address(this)));
    IWETH(_WETH).withdraw(amountETH);
    TransferHelper.safeTransferETH(to, amountETH);
  }

  function removeLiquidityETHWithPermitSupportingFeeOnTransferTokens(
    address token,
    uint256 liquidity,
    uint256 amountTokenMin,
    uint256 amountETHMin,
    address to,
    uint256 deadline,
    bool approveMax,
    uint8 v,
    bytes32 r,
    bytes32 s
  ) external virtual override returns (uint256 amountETH) {
    address pair = UniswapV2Library.pairFor(_factory, token, _WETH);
    uint256 value = approveMax ? uint256(-1) : liquidity;
    IUniswapV2Pair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
    amountETH = removeLiquidityETHSupportingFeeOnTransferTokens(token, liquidity, amountTokenMin, amountETHMin, to, deadline);
  }

  // **** SWAP ****
  // requires the initial amount to have already been sent to the first pair
  function _swap(
    uint256[] memory amounts,
    address[] memory path,
    address _to
  ) internal virtual {
    for (uint256 i; i < path.length - 1; i++) {
      (address input, address output) = (path[i], path[i + 1]);
      (address token0, ) = UniswapV2Library.sortTokens(input, output);
      uint256 amountOut = amounts[i + 1];
      (uint256 amount0Out, uint256 amount1Out) = input == token0 ? (uint256(0), amountOut) : (amountOut, uint256(0));
      address to = i < path.length - 2 ? UniswapV2Library.pairFor(_factory, output, path[i + 2]) : _to;
      IUniswapV2Pair(UniswapV2Library.pairFor(_factory, input, output)).swap(amount0Out, amount1Out, to, new bytes(0));
    }
  }

  function swapExactTokensForTokens(
    uint256 amountIn,
    uint256 amountOutMin,
    address[] calldata path,
    address to,
    uint256 deadline
  ) external virtual override ensure(deadline) returns (uint256[] memory amounts) {
    amounts = UniswapV2Library.getAmountsOut(_factory, amountIn, path);
    // console.log("AMOUNT: %s factory: %s", amounts, _factory);
    require(amounts[amounts.length - 1] >= amountOutMin, "UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT");
    TransferHelper.safeTransferFrom(path[0], msg.sender, UniswapV2Library.pairFor(_factory, path[0], path[1]), amounts[0]);
    _swap(amounts, path, to);
  }

  function swapTokensForExactTokens(
    uint256 amountOut,
    uint256 amountInMax,
    address[] calldata path,
    address to,
    uint256 deadline
  ) external virtual override ensure(deadline) returns (uint256[] memory amounts) {
    amounts = UniswapV2Library.getAmountsIn(_factory, amountOut, path);
    require(amounts[0] <= amountInMax, "UniswapV2Router: EXCESSIVE_INPUT_AMOUNT");
    TransferHelper.safeTransferFrom(path[0], msg.sender, UniswapV2Library.pairFor(_factory, path[0], path[1]), amounts[0]);
    _swap(amounts, path, to);
  }

  function swapExactETHForTokens(
    uint256 amountOutMin,
    address[] calldata path,
    address to,
    uint256 deadline
  ) external payable virtual override ensure(deadline) returns (uint256[] memory amounts) {
    require(path[0] == _WETH, "UniswapV2Router: INVALID_PATH");
    amounts = UniswapV2Library.getAmountsOut(_factory, msg.value, path);
    require(amounts[amounts.length - 1] >= amountOutMin, "UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT");
    IWETH(_WETH).deposit{value: amounts[0]}();
    assert(IWETH(_WETH).transfer(UniswapV2Library.pairFor(_factory, path[0], path[1]), amounts[0]));
    _swap(amounts, path, to);
  }

  function swapTokensForExactETH(
    uint256 amountOut,
    uint256 amountInMax,
    address[] calldata path,
    address to,
    uint256 deadline
  ) external virtual override ensure(deadline) returns (uint256[] memory amounts) {
    require(path[path.length - 1] == _WETH, "UniswapV2Router: INVALID_PATH");
    amounts = UniswapV2Library.getAmountsIn(_factory, amountOut, path);
    require(amounts[0] <= amountInMax, "UniswapV2Router: EXCESSIVE_INPUT_AMOUNT");
    TransferHelper.safeTransferFrom(path[0], msg.sender, UniswapV2Library.pairFor(_factory, path[0], path[1]), amounts[0]);
    _swap(amounts, path, address(this));
    IWETH(_WETH).withdraw(amounts[amounts.length - 1]);
    TransferHelper.safeTransferETH(to, amounts[amounts.length - 1]);
  }

  function swapExactTokensForETH(
    uint256 amountIn,
    uint256 amountOutMin,
    address[] calldata path,
    address to,
    uint256 deadline
  ) external virtual override ensure(deadline) returns (uint256[] memory amounts) {
    require(path[path.length - 1] == _WETH, "UniswapV2Router: INVALID_PATH");
    amounts = UniswapV2Library.getAmountsOut(_factory, amountIn, path);
    require(amounts[amounts.length - 1] >= amountOutMin, "UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT");
    TransferHelper.safeTransferFrom(path[0], msg.sender, UniswapV2Library.pairFor(_factory, path[0], path[1]), amounts[0]);
    _swap(amounts, path, address(this));
    IWETH(_WETH).withdraw(amounts[amounts.length - 1]);
    TransferHelper.safeTransferETH(to, amounts[amounts.length - 1]);
  }

  function swapETHForExactTokens(
    uint256 amountOut,
    address[] calldata path,
    address to,
    uint256 deadline
  ) external payable virtual override ensure(deadline) returns (uint256[] memory amounts) {
    require(path[0] == _WETH, "UniswapV2Router: INVALID_PATH");
    amounts = UniswapV2Library.getAmountsIn(_factory, amountOut, path);
    require(amounts[0] <= msg.value, "UniswapV2Router: EXCESSIVE_INPUT_AMOUNT");
    IWETH(_WETH).deposit{value: amounts[0]}();
    assert(IWETH(_WETH).transfer(UniswapV2Library.pairFor(_factory, path[0], path[1]), amounts[0]));
    _swap(amounts, path, to);
    // refund dust eth, if any
    if (msg.value > amounts[0]) TransferHelper.safeTransferETH(msg.sender, msg.value - amounts[0]);
  }

  // **** SWAP (supporting fee-on-transfer tokens) ****
  // requires the initial amount to have already been sent to the first pair
  function _swapSupportingFeeOnTransferTokens(address[] memory path, address _to) internal virtual {
    for (uint256 i; i < path.length - 1; i++) {
      (address input, address output) = (path[i], path[i + 1]);
      (address token0, ) = UniswapV2Library.sortTokens(input, output);
      IUniswapV2Pair pair = IUniswapV2Pair(UniswapV2Library.pairFor(_factory, input, output));
      uint256 amountInput;
      uint256 amountOutput;
      {
        // scope to avoid stack too deep errors
        (uint256 reserve0, uint256 reserve1, ) = pair.getReserves();
        (uint256 reserveInput, uint256 reserveOutput) = input == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
        amountInput = IERC20Uniswap(input).balanceOf(address(pair)).sub(reserveInput);
        amountOutput = UniswapV2Library.getAmountOut(amountInput, reserveInput, reserveOutput);
      }
      (uint256 amount0Out, uint256 amount1Out) = input == token0 ? (uint256(0), amountOutput) : (amountOutput, uint256(0));
      address to = i < path.length - 2 ? UniswapV2Library.pairFor(_factory, output, path[i + 2]) : _to;
      pair.swap(amount0Out, amount1Out, to, new bytes(0));
    }
  }

  function swapExactTokensForTokensSupportingFeeOnTransferTokens(
    uint256 amountIn,
    uint256 amountOutMin,
    address[] calldata path,
    address to,
    uint256 deadline
  ) external virtual override ensure(deadline) {
    TransferHelper.safeTransferFrom(path[0], msg.sender, UniswapV2Library.pairFor(_factory, path[0], path[1]), amountIn);
    uint256 balanceBefore = IERC20Uniswap(path[path.length - 1]).balanceOf(to);
    _swapSupportingFeeOnTransferTokens(path, to);
    require(
      IERC20Uniswap(path[path.length - 1]).balanceOf(to).sub(balanceBefore) >= amountOutMin,
      "UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT"
    );
  }

  function swapExactETHForTokensSupportingFeeOnTransferTokens(
    uint256 amountOutMin,
    address[] calldata path,
    address to,
    uint256 deadline
  ) external payable virtual override ensure(deadline) {
    require(path[0] == _WETH, "UniswapV2Router: INVALID_PATH");
    uint256 amountIn = msg.value;
    IWETH(_WETH).deposit{value: amountIn}();
    assert(IWETH(_WETH).transfer(UniswapV2Library.pairFor(_factory, path[0], path[1]), amountIn));
    uint256 balanceBefore = IERC20Uniswap(path[path.length - 1]).balanceOf(to);
    _swapSupportingFeeOnTransferTokens(path, to);
    require(
      IERC20Uniswap(path[path.length - 1]).balanceOf(to).sub(balanceBefore) >= amountOutMin,
      "UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT"
    );
  }

  function swapExactTokensForETHSupportingFeeOnTransferTokens(
    uint256 amountIn,
    uint256 amountOutMin,
    address[] calldata path,
    address to,
    uint256 deadline
  ) external virtual override ensure(deadline) {
    require(path[path.length - 1] == _WETH, "UniswapV2Router: INVALID_PATH");
    TransferHelper.safeTransferFrom(path[0], msg.sender, UniswapV2Library.pairFor(_factory, path[0], path[1]), amountIn);
    _swapSupportingFeeOnTransferTokens(path, address(this));
    uint256 amountOut = IERC20Uniswap(_WETH).balanceOf(address(this));
    require(amountOut >= amountOutMin, "UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT");
    IWETH(_WETH).withdraw(amountOut);
    TransferHelper.safeTransferETH(to, amountOut);
  }

  // **** LIBRARY FUNCTIONS ****
  function quote(
    uint256 amountA,
    uint256 reserveA,
    uint256 reserveB
  ) public pure virtual override returns (uint256 amountB) {
    return UniswapV2Library.quote(amountA, reserveA, reserveB);
  }

  function getAmountOut(
    uint256 amountIn,
    uint256 reserveIn,
    uint256 reserveOut
  ) public pure virtual override returns (uint256 amountOut) {
    return UniswapV2Library.getAmountOut(amountIn, reserveIn, reserveOut);
  }

  function getAmountIn(
    uint256 amountOut,
    uint256 reserveIn,
    uint256 reserveOut
  ) public pure virtual override returns (uint256 amountIn) {
    return UniswapV2Library.getAmountIn(amountOut, reserveIn, reserveOut);
  }

  function getAmountsOut(uint256 amountIn, address[] memory path) public view virtual override returns (uint256[] memory amounts) {
    return UniswapV2Library.getAmountsOut(_factory, amountIn, path);
  }

  function getAmountsIn(uint256 amountOut, address[] memory path) public view virtual override returns (uint256[] memory amounts) {
    return UniswapV2Library.getAmountsIn(_factory, amountOut, path);
  }
}
