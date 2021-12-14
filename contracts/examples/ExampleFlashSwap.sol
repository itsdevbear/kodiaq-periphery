pragma solidity =0.6.6;

import '@berachain/kodiaq-core/contracts/interfaces/IKodiaqCallee.sol';
import '@berachain/kodiaq-core/contracts/interfaces/IKodiaqPair.sol';
import '../libraries/KodiaqLibrary.sol';
import '../interfaces/V1/IUniswapV1Factory.sol';
import '../interfaces/V1/IUniswapV1Exchange.sol';
import '../interfaces/IKodiaqRouter01.sol';
import '../interfaces/IERC20.sol';
import '../interfaces/IWBERA.sol';

contract ExampleFlashSwap is IKodiaqCallee {
    IUniswapV1Factory immutable factoryV1;
    address immutable factory;
    IWBERA immutable WBERA;

    constructor(address _factory, address _factoryV1, address router) public {
        factoryV1 = IUniswapV1Factory(_factoryV1);
        factory = _factory;
        WBERA = IWBERA(IKodiaqRouter01(router).WBERA());
    }

    // needs to accept BERA from any V1 exchange and WBERA. ideally this could be enforced, as in the router,
    // but it's not possible because it requires a call to the v1 factory, which takes too much gas
    receive() external payable {}

    // gets tokens/WBERA via a V2 flash swap, swaps for the BERA/tokens on V1, repays V2, and keeps the rest!
    function kodiaqCall(address sender, uint amount0, uint amount1, bytes calldata data) external override {
        address[] memory path = new address[](2);
        uint amountToken;
        uint amountBERA;
        { // scope for token{0,1}, avoids stack too deep errors
        address token0 = IKodiaqPair(msg.sender).token0();
        address token1 = IKodiaqPair(msg.sender).token1();
        assert(msg.sender == KodiaqLibrary.pairFor(factory, token0, token1)); // ensure that msg.sender is actually a V2 pair
        assert(amount0 == 0 || amount1 == 0); // this strategy is unidirectional
        path[0] = amount0 == 0 ? token0 : token1;
        path[1] = amount0 == 0 ? token1 : token0;
        amountToken = token0 == address(WBERA) ? amount1 : amount0;
        amountBERA = token0 == address(WBERA) ? amount0 : amount1;
        }

        assert(path[0] == address(WBERA) || path[1] == address(WBERA)); // this strategy only works with a V2 WBERA pair
        IERC20 token = IERC20(path[0] == address(WBERA) ? path[1] : path[0]);
        IUniswapV1Exchange exchangeV1 = IUniswapV1Exchange(factoryV1.getExchange(address(token))); // get V1 exchange

        if (amountToken > 0) {
            (uint minBERA) = abi.decode(data, (uint)); // slippage parameter for V1, passed in by caller
            token.approve(address(exchangeV1), amountToken);
            uint amountReceived = exchangeV1.tokenToEthSwapInput(amountToken, minBERA, uint(-1));
            uint amountRequired = KodiaqLibrary.getAmountsIn(factory, amountToken, path)[0];
            assert(amountReceived > amountRequired); // fail if we didn't get enough BERA back to repay our flash loan
            WBERA.deposit{value: amountRequired}();
            assert(WBERA.transfer(msg.sender, amountRequired)); // return WBERA to V2 pair
            (bool success,) = sender.call{value: amountReceived - amountRequired}(new bytes(0)); // keep the rest! (BERA)
            assert(success);
        } else {
            (uint minTokens) = abi.decode(data, (uint)); // slippage parameter for V1, passed in by caller
            WBERA.withdraw(amountBERA);
            uint amountReceived = exchangeV1.ethToTokenSwapInput{value: amountBERA}(minTokens, uint(-1));
            uint amountRequired = KodiaqLibrary.getAmountsIn(factory, amountBERA, path)[0];
            assert(amountReceived > amountRequired); // fail if we didn't get enough tokens back to repay our flash loan
            assert(token.transfer(msg.sender, amountRequired)); // return tokens to V2 pair
            assert(token.transfer(sender, amountReceived - amountRequired)); // keep the rest! (tokens)
        }
    }
}
