// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
contract Dex is ERC20 {
    IERC20 tokenX;
    IERC20 tokenY;
    uint112 private reserveX; 
    uint112 private reserveY;
    constructor(address _tokenX, address _tokenY )ERC20("DEX_implement","E3X"){
        tokenX = IERC20(_tokenX);
        tokenY = IERC20(_tokenY);

    }
     uint256 private unlocked = 1;

    modifier lock() {
        require(unlocked == 1, " LOCKED");
        unlocked = 0;
        _;
        unlocked = 1;
    }
    // 최소 minimum_LP_Token 보다 LP 토큰이 많이 발급되어야함.
    function addLiquidity(uint amountX, uint amountY, uint minimumLPToken)public returns (uint){
        require(amountX != 0 && amountY != 0, "NO_ZERO_AMOUNT");
        require(IERC20(tokenX).allowance(msg.sender, address(this)) >= amountX, "ERC20: insufficient allowance");
        require(IERC20(tokenY).allowance(msg.sender, address(this)) >= amountY, "ERC20: insufficient allowance");
        require(IERC20(tokenX).balanceOf(msg.sender) >= amountX, "ERC20: transfer amount exceeds balance");
        require(IERC20(tokenY).balanceOf(msg.sender) >= amountY, "ERC20: transfer amount exceeds balance");

        // 풀에 추가
        IERC20(tokenX).transferFrom(msg.sender, address(this), amountX);
        IERC20(tokenY).transferFrom(msg.sender, address(this), amountY);

        //lp 발행
        uint256 mintedLPToken = this.mint(msg.sender);
        require(mintedLPToken >= minimumLPToken);
        return mintedLPToken;
    }
    
    
   
    function safeTransfer(address token, address to, uint256 value) private {
        bytes4 SELECTOR = bytes4(keccak256(bytes("transfer(address,uint256)")));
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(SELECTOR, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), " TRANSFER_FAILED");
    }

    function burn(address to) external lock returns (uint256 amountX, uint256 amountY) {
        uint256 balanceX = IERC20(tokenX).balanceOf(address(this));
        uint256 balanceY = IERC20(tokenY).balanceOf(address(this));
        uint256 totalSupply = totalSupply();
        uint256 liquidity = balanceOf(address(this));

        amountX = liquidity * balanceX / totalSupply;
        amountY = liquidity * balanceY / totalSupply;

        require(amountX > 0 && amountY > 0, "INSUFFICENT_LIQUIDITY_BURNED");
        _burn(address(this), liquidity);
        safeTransfer(address(tokenX), msg.sender, amountX);
        safeTransfer(address(tokenY), msg.sender, amountY);

        balanceX = IERC20(tokenX).balanceOf(address(this));
        balanceY = IERC20(tokenY).balanceOf(address(this));

        update(balanceX, balanceY);

    }
    function removeLiquidity(uint lpToken, uint minAmountX, uint minAmountY)public returns (uint, uint){
        // function removeLiquidity(uint256 lpTokens, uint256 minAmountX, uint256 minAmountY) external returns (uint amountX, uint amountY) {
        // require(ERC20(this).balanceOf(msg.sender) == 0,"wtf");
        transferFrom(msg.sender, address(this), lpToken);
        
        (uint afterBurnAmountX, uint afterBurnAmountY) = this.burn(msg.sender);
        require(afterBurnAmountX >= minAmountX, "INSUFFICIENT_X");
        require(afterBurnAmountY >= minAmountY, "INSUFFICIENT_Y");
        return (afterBurnAmountX, afterBurnAmountY);
    }

    function mint(address to)public lock returns (uint256 liquidity) {
        // balance : 스마트 계약의 실시간 토큰 잔액 (실시간 ERC20반영))
        // reserve : 스마트 계약에 기록된 예치량 (트랜잭션 전)
        // amount : 실시간 ERC20(유저가 이미 보냄) - 트랜잭션 전 = 얼마나 보냈는지
        (uint112 _reserveX, uint112 _reserveY) = getReserves();
        uint256 balanceX = IERC20(tokenX).balanceOf(address(this));
        uint256 balanceY = IERC20(tokenY).balanceOf(address(this));
        uint256 amountX = balanceX - _reserveX;
        uint256 amountY = balanceY - _reserveY;
        uint256 totalSupply = totalSupply(); // 그리고 이제 토큰 실제 보유량 - 추적하고 있는 양 = 해서 얼마나 보냈는지 파악하는거지.

        if (totalSupply == 0) {
            liquidity = Math.sqrt(amountX * amountY);
        } else {
            
            liquidity = Math.min(amountX * totalSupply / reserveX, amountY * totalSupply / reserveY); // 이만큼 발행한다.
        }
        
        require(liquidity > 0, "INSUFFICIENT_LIQUIDITY_MINTED");
        _mint(to, liquidity);

        update(balanceX, balanceY);

    }
    function update(uint256 _balanceX, uint256 _balanceY) private {
    
        reserveX = uint112(_balanceX);
        reserveY = uint112(_balanceY);
    }
    
    
    
    function getReserves() private view returns (uint112 _reserveX, uint112 _reserveY) {
        _reserveX = reserveX;
        _reserveY = reserveY;

    }
    
    function swap(uint256 amountXIn, uint256 amountYIn, uint256 minTokenOut) external returns (uint)  {
        require((!(amountXIn == 0 && amountYIn == 0)) && !(amountXIn != 0 && amountYIn !=0), "INSUFFICIENT_SWAP_PARAMETER :((");
        (uint256 _reserveX, uint256 _reserveY) = getReserves();

        if(amountYIn == 0){
            uint amountYOut = _reserveY - ( _reserveX * _reserveY ) / ( _reserveX+amountXIn );
            uint amountYOutWithFee = ( amountYOut * 999 ) / 1000;
            tokenX.transferFrom(msg.sender, address(this), amountXIn);
            tokenY.transfer(msg.sender, amountYOutWithFee);
            require(amountYOut >= minTokenOut,"test");
            return amountYOutWithFee;
        
        }else{
            uint amountXOut = _reserveX - ( _reserveY * _reserveX ) / ( _reserveY+amountYIn );
            uint amountXOutWithFee = ( amountXOut * 999 ) / 1000;
            tokenY.transferFrom(msg.sender, address(this), amountYIn);
            tokenX.transfer(msg.sender, amountXOutWithFee);
            require(amountXOut >= minTokenOut);
            return amountXOutWithFee;
        }
        
        
    }
   
    function transferFrom(address from, address to, uint256 value) public override returns (bool) {
        if (to == address(this))
            _transfer(from, to, value);
        else
            super.transferFrom(from, to, value);
        return true;
    }
}
