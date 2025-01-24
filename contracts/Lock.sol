// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.22;


import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract TokenA is ERC20 {
    constructor() ERC20("TokenA", "A") {
        _mint(0x5B38Da6a701c568545dCfcB03FcB875f56beddC4, 1000000 * 10 ** decimals());
    }
}


contract TokenB is ERC20 {
    constructor() ERC20("TokenB", "B") {
        _mint(0xAb8483F64d9C6d1EcF9b849Ae677dD3315835cb2, 1000000 * 10 ** decimals());
    }
}

interface iLimitOrder {
    function fillOffer(uint256 _amountOffered, address _recipient) external;
    function consolidateOffer(address _otherOffer) external;
    function offerer() external view returns (address);
    function isActive() external view returns (bool);
    function amountOfferedRemaining() external view returns (uint256);
    function amountOffered() external view returns (uint256);
    function amountDesired() external view returns (uint256);
    function offeredToken() external view returns (address);
    function desiredToken() external view returns (address);
}

contract LimitOrder is ReentrancyGuard {
    using SafeERC20 for IERC20;
    event OfferFilled(uint256 amountOfferSold, uint256 amountDesiredReceived, address recipient);
    event OfferRevoked();
    event OfferConsolidated(address _otherOffer, uint256 amountDesiredReceived);
    address public immutable offerer;
    address public immutable offeredToken;
    address public immutable desiredToken;
    uint256 public immutable amountOffered;
    uint256 public immutable amountDesired;
    uint256 public amountOfferedRemaining;
    uint256 public constant scalar = 10**18;
    bool public isActive;

    constructor(address _offeredToken, address _desiredToken, uint256 _amountOffered, uint256 _amountDesired) {
        offerer = msg.sender;
        offeredToken=_offeredToken;
        desiredToken=_desiredToken;
        amountOffered = _amountOffered;
        amountOfferedRemaining = amountOffered;
        amountDesired=_amountDesired;
        isActive=true;
    }
    
    function revokeOffer() external {
        require(msg.sender == offerer, "Only offerer can revoke offer");
        isActive = false;
        emit OfferRevoked();
    }
    function fillOffer(uint256 _amountOffered, address _recipient) external {
        require(isActive, "Offer is not active");
        require(_amountOffered <= amountOfferedRemaining, "Not enough tokens offered");
        amountOfferedRemaining -= _amountOffered;
        uint256 scaledAmountDesired = scalar *_amountOffered * amountDesired / amountOffered;
        IERC20(desiredToken).safeTransferFrom(msg.sender, offerer, scaledAmountDesired/scalar);
        IERC20(offeredToken).safeTransferFrom(offerer, _recipient, _amountOffered);
        emit OfferFilled(_amountOffered, scaledAmountDesired/scalar, _recipient);
    }
    
    function consolidateOffer(address _otherOffer) external nonReentrant {
        iLimitOrder otherOffer = iLimitOrder(_otherOffer);
        uint256 scaledRatioOther = scalar * otherOffer.amountOffered() / otherOffer.amountDesired(); // Other's Offered over Desired...
        uint256 scaledRatioThis = scalar * amountDesired / amountOffered; // is This's Desired over Offered
        require(scaledRatioThis<=scaledRatioOther, "Only if the other price is higher."); 
        uint256 amountDesiredToFill = otherOffer.amountOffered();
        if (amountOffered >= otherOffer.amountDesired()) { 
            amountDesiredToFill = otherOffer.amountOffered();
        }
        else {
            amountDesiredToFill = amountOffered  * scaledRatioOther / scalar;
        }
        
        uint256 scaledAmountOfferNeeded = amountDesiredToFill * scalar * otherOffer.amountDesired() / otherOffer.amountOffered();
        uint256 balanceOfferedBefore = IERC20(offeredToken).balanceOf(address(this));
        uint256 balanceDesiredBefore = IERC20(desiredToken).balanceOf(address(this));
        IERC20(offeredToken).safeTransferFrom(offerer, address(this), scaledAmountOfferNeeded/scalar);
        IERC20(offeredToken).approve(_otherOffer, scaledAmountOfferNeeded);
        otherOffer.fillOffer(amountDesiredToFill, address(this));
        uint256 balanceDesiredAfter = IERC20(desiredToken).balanceOf(address(this));
        uint256 balanceOfferedAfter = IERC20(offeredToken).balanceOf(address(this));
        uint256 amountOfferedSpent = balanceOfferedAfter-balanceOfferedBefore;
        amountOfferedRemaining -= amountOfferedSpent;
        uint256 amountDesiredReceived = balanceDesiredAfter-balanceDesiredBefore;
        require(amountDesiredReceived >= amountDesiredToFill, "Not enough.");
        IERC20(desiredToken).safeTransfer(offerer, balanceDesiredAfter);
        emit OfferConsolidated(_otherOffer, amountDesiredReceived);
    }
    
}
