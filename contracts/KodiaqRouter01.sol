pragma solidity =0.6.6;

import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol';
import '@uniswap/lib/contracts/libraries/TransferHelper.sol';

import './libraries/KodiaqLibrary.sol';
import './interfaces/IKodiaqRouter01.sol';
import './interfaces/IERC20.sol';
import './interfaces/IWBERA.sol';

contract KodiaqRouter01 is IKodiaqRouter01 {
    address public immutable override factory;
    address public immutable override WBERA;

    modifier ensure(uint deadline) {
        require(deadline >= block.timestamp, 'KodiaqRouter: EXPIRED');
        _;
    }

    constructor(address _factory, address _WBERA) public {
        factory = _factory;
        WBERA = _WBERA;
    }

    receive() external payable {
        assert(msg.sender == WBERA); // only accept BERA via fallback from the WBERA contract
    }

    // **** ADD LIQUIDITY ****
    function _addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin
    ) private returns (uint amountA, uint amountB) {
        // create the pair if it doesn't exist yet
        if (IUniswapV2Factory(factory).getPair(tokenA, tokenB) == address(0)) {
            IUniswapV2Factory(factory).createPair(tokenA, tokenB);
        }
        (uint reserveA, uint reserveB) = KodiaqLibrary.getReserves(factory, tokenA, tokenB);
        if (reserveA == 0 && reserveB == 0) {
            (amountA, amountB) = (amountADesired, amountBDesired);
        } else {
            uint amountBOptimal = KodiaqLibrary.quote(amountADesired, reserveA, reserveB);
            if (amountBOptimal <= amountBDesired) {
                require(amountBOptimal >= amountBMin, 'KodiaqRouter: INSUFFICIENT_B_AMOUNT');
                (amountA, amountB) = (amountADesired, amountBOptimal);
            } else {
                uint amountAOptimal = KodiaqLibrary.quote(amountBDesired, reserveB, reserveA);
                assert(amountAOptimal <= amountADesired);
                require(amountAOptimal >= amountAMin, 'KodiaqRouter: INSUFFICIENT_A_AMOUNT');
                (amountA, amountB) = (amountAOptimal, amountBDesired);
            }
        }
    }
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external override ensure(deadline) returns (uint amountA, uint amountB, uint liquidity) {
        (amountA, amountB) = _addLiquidity(tokenA, tokenB, amountADesired, amountBDesired, amountAMin, amountBMin);
        address pair = KodiaqLibrary.pairFor(factory, tokenA, tokenB);
        TransferHelper.safeTransferFrom(tokenA, msg.sender, pair, amountA);
        TransferHelper.safeTransferFrom(tokenB, msg.sender, pair, amountB);
        liquidity = IUniswapV2Pair(pair).mint(to);
    }
    function addLiquidityBERA(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountBERAMin,
        address to,
        uint deadline
    ) external override payable ensure(deadline) returns (uint amountToken, uint amountBERA, uint liquidity) {
        (amountToken, amountBERA) = _addLiquidity(
            token,
            WBERA,
            amountTokenDesired,
            msg.value,
            amountTokenMin,
            amountBERAMin
        );
        address pair = KodiaqLibrary.pairFor(factory, token, WBERA);
        TransferHelper.safeTransferFrom(token, msg.sender, pair, amountToken);
        IWBERA(WBERA).deposit{value: amountBERA}();
        assert(IWBERA(WBERA).transfer(pair, amountBERA));
        liquidity = IUniswapV2Pair(pair).mint(to);
        if (msg.value > amountBERA) TransferHelper.safeTransferETH(msg.sender, msg.value - amountBERA); // refund dust BERA, if any
    }

    // **** REMOVE LIQUIDITY ****
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) public override ensure(deadline) returns (uint amountA, uint amountB) {
        address pair = KodiaqLibrary.pairFor(factory, tokenA, tokenB);
        IUniswapV2Pair(pair).transferFrom(msg.sender, pair, liquidity); // send liquidity to pair
        (uint amount0, uint amount1) = IUniswapV2Pair(pair).burn(to);
        (address token0,) = KodiaqLibrary.sortTokens(tokenA, tokenB);
        (amountA, amountB) = tokenA == token0 ? (amount0, amount1) : (amount1, amount0);
        require(amountA >= amountAMin, 'KodiaqRouter: INSUFFICIENT_A_AMOUNT');
        require(amountB >= amountBMin, 'KodiaqRouter: INSUFFICIENT_B_AMOUNT');
    }
    function removeLiquidityBERA(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountBERAMin,
        address to,
        uint deadline
    ) public override ensure(deadline) returns (uint amountToken, uint amountBERA) {
        (amountToken, amountBERA) = removeLiquidity(
            token,
            WBERA,
            liquidity,
            amountTokenMin,
            amountBERAMin,
            address(this),
            deadline
        );
        TransferHelper.safeTransfer(token, to, amountToken);
        IWBERA(WBERA).withdraw(amountBERA);
        TransferHelper.safeTransferETH(to, amountBERA);
    }
    function removeLiquidityWithPermit(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external override returns (uint amountA, uint amountB) {
        address pair = KodiaqLibrary.pairFor(factory, tokenA, tokenB);
        uint value = approveMax ? uint(-1) : liquidity;
        IUniswapV2Pair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        (amountA, amountB) = removeLiquidity(tokenA, tokenB, liquidity, amountAMin, amountBMin, to, deadline);
    }
    function removeLiquidityBERAWithPermit(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountBERAMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external override returns (uint amountToken, uint amountBERA) {
        address pair = KodiaqLibrary.pairFor(factory, token, WBERA);
        uint value = approveMax ? uint(-1) : liquidity;
        IUniswapV2Pair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        (amountToken, amountBERA) = removeLiquidityBERA(token, liquidity, amountTokenMin, amountBERAMin, to, deadline);
    }

    // **** SWAP ****
    // requires the initial amount to have already been sent to the first pair
    function _swap(uint[] memory amounts, address[] memory path, address _to) private {
        for (uint i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0,) = KodiaqLibrary.sortTokens(input, output);
            uint amountOut = amounts[i + 1];
            (uint amount0Out, uint amount1Out) = input == token0 ? (uint(0), amountOut) : (amountOut, uint(0));
            address to = i < path.length - 2 ? KodiaqLibrary.pairFor(factory, output, path[i + 2]) : _to;
            IUniswapV2Pair(KodiaqLibrary.pairFor(factory, input, output)).swap(amount0Out, amount1Out, to, new bytes(0));
        }
    }
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external override ensure(deadline) returns (uint[] memory amounts) {
        amounts = KodiaqLibrary.getAmountsOut(factory, amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin, 'KodiaqRouter: INSUFFICIENT_OUTPUT_AMOUNT');
        TransferHelper.safeTransferFrom(path[0], msg.sender, KodiaqLibrary.pairFor(factory, path[0], path[1]), amounts[0]);
        _swap(amounts, path, to);
    }
    function swapTokensForExactTokens(
        uint amountOut,
        uint amountInMax,
        address[] calldata path,
        address to,
        uint deadline
    ) external override ensure(deadline) returns (uint[] memory amounts) {
        amounts = KodiaqLibrary.getAmountsIn(factory, amountOut, path);
        require(amounts[0] <= amountInMax, 'KodiaqRouter: EXCESSIVE_INPUT_AMOUNT');
        TransferHelper.safeTransferFrom(path[0], msg.sender, KodiaqLibrary.pairFor(factory, path[0], path[1]), amounts[0]);
        _swap(amounts, path, to);
    }
    function swapExactBERAForTokens(uint amountOutMin, address[] calldata path, address to, uint deadline)
        external
        override
        payable
        ensure(deadline)
        returns (uint[] memory amounts)
    {
        require(path[0] == WBERA, 'KodiaqRouter: INVALID_PATH');
        amounts = KodiaqLibrary.getAmountsOut(factory, msg.value, path);
        require(amounts[amounts.length - 1] >= amountOutMin, 'KodiaqRouter: INSUFFICIENT_OUTPUT_AMOUNT');
        IWBERA(WBERA).deposit{value: amounts[0]}();
        assert(IWBERA(WBERA).transfer(KodiaqLibrary.pairFor(factory, path[0], path[1]), amounts[0]));
        _swap(amounts, path, to);
    }
    function swapTokensForExactBERA(uint amountOut, uint amountInMax, address[] calldata path, address to, uint deadline)
        external
        override
        ensure(deadline)
        returns (uint[] memory amounts)
    {
        require(path[path.length - 1] == WBERA, 'KodiaqRouter: INVALID_PATH');
        amounts = KodiaqLibrary.getAmountsIn(factory, amountOut, path);
        require(amounts[0] <= amountInMax, 'KodiaqRouter: EXCESSIVE_INPUT_AMOUNT');
        TransferHelper.safeTransferFrom(path[0], msg.sender, KodiaqLibrary.pairFor(factory, path[0], path[1]), amounts[0]);
        _swap(amounts, path, address(this));
        IWBERA(WBERA).withdraw(amounts[amounts.length - 1]);
        TransferHelper.safeTransferETH(to, amounts[amounts.length - 1]);
    }
    function swapExactTokensForBERA(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline)
        external
        override
        ensure(deadline)
        returns (uint[] memory amounts)
    {
        require(path[path.length - 1] == WBERA, 'KodiaqRouter: INVALID_PATH');
        amounts = KodiaqLibrary.getAmountsOut(factory, amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin, 'KodiaqRouter: INSUFFICIENT_OUTPUT_AMOUNT');
        TransferHelper.safeTransferFrom(path[0], msg.sender, KodiaqLibrary.pairFor(factory, path[0], path[1]), amounts[0]);
        _swap(amounts, path, address(this));
        IWBERA(WBERA).withdraw(amounts[amounts.length - 1]);
        TransferHelper.safeTransferETH(to, amounts[amounts.length - 1]);
    }
    function swapBERAForExactTokens(uint amountOut, address[] calldata path, address to, uint deadline)
        external
        override
        payable
        ensure(deadline)
        returns (uint[] memory amounts)
    {
        require(path[0] == WBERA, 'KodiaqRouter: INVALID_PATH');
        amounts = KodiaqLibrary.getAmountsIn(factory, amountOut, path);
        require(amounts[0] <= msg.value, 'KodiaqRouter: EXCESSIVE_INPUT_AMOUNT');
        IWBERA(WBERA).deposit{value: amounts[0]}();
        assert(IWBERA(WBERA).transfer(KodiaqLibrary.pairFor(factory, path[0], path[1]), amounts[0]));
        _swap(amounts, path, to);
        if (msg.value > amounts[0]) TransferHelper.safeTransferETH(msg.sender, msg.value - amounts[0]); // refund dust BERA, if any
    }

    function quote(uint amountA, uint reserveA, uint reserveB) public pure override returns (uint amountB) {
        return KodiaqLibrary.quote(amountA, reserveA, reserveB);
    }

    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut) public pure override returns (uint amountOut) {
        return KodiaqLibrary.getAmountOut(amountIn, reserveIn, reserveOut);
    }

    function getAmountIn(uint amountOut, uint reserveIn, uint reserveOut) public pure override returns (uint amountIn) {
        return KodiaqLibrary.getAmountOut(amountOut, reserveIn, reserveOut);
    }

    function getAmountsOut(uint amountIn, address[] memory path) public view override returns (uint[] memory amounts) {
        return KodiaqLibrary.getAmountsOut(factory, amountIn, path);
    }

    function getAmountsIn(uint amountOut, address[] memory path) public view override returns (uint[] memory amounts) {
        return KodiaqLibrary.getAmountsIn(factory, amountOut, path);
    }
}
