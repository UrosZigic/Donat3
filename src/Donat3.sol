//SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "openzeppelin-contracts/contracts/access/Ownable2Step.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "./interfaces/external/IWETH9.sol";
import "v2-core/interfaces/IUniswapV2Factory.sol";
import "v2-core/interfaces/IUniswapV2Pair.sol";
import "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

/// @title Donat3 - Humanitarian Foundation Protocol
/// @author UrosZigic
contract Donat3 is Ownable2Step, ReentrancyGuard {

    using SafeERC20 for IERC20;

    error CampaignNotFound();
    error WrongCampaignStatus();
    error CantWithdraw();
    error CantDonate();
    error CantDonateZero();
    error InsufficientAllowance();
    
    uint256 public campaignsCounter = 0;
    mapping(uint256 => Campaign) public campaigns;
    IUniswapV2Factory public uniswapFactory;
    IUniswapV2Pair public uniswapPair;
    address public immutable WETH9Address;
    address public immutable DAIAddress;

    struct Campaign {
        string title;
        string description;
        string image;
        Currency currency;
        uint256 requiredSum;
        uint256 collectedSum;
        address[] donatorsAdresses;
        uint256[] donatorsAmounts;
        address withdrawalAddress;
        CampaignStatus status;
    }

    enum CampaignStatus {
        Open,
        Closed,
        WaitingAdminAction,
        WaitingWithdrawal,
        Successful
    }

    enum Currency {
        ETH,
        DAI
    }

    event CampaignCreated(string indexed title, uint256 indexed requiredSum);
    event Donated(address indexed donator, uint256 indexed amount, string indexed title);
    event Withdrawn(string indexed title, address indexed withdrawalAddress, uint256 indexed collectedSum);
    event WaitingAdminAction(string indexed title);


    constructor(address _admin, address _factoryAddress, address _WETHAddress, address _DAIAddress) Ownable(_admin) {
        uniswapFactory = IUniswapV2Factory(_factoryAddress);

        WETH9Address = _WETHAddress;
        DAIAddress = _DAIAddress;

        uniswapPair = IUniswapV2Pair(uniswapFactory.getPair(_WETHAddress, _DAIAddress));
    }

    /**
     * @notice Receives all funds that are sent to the contract together with the additional data that does not correspond to the existing function
     */
    fallback() external payable {}

    /**
     * @notice Receives all funds that are sent to the contract without additional data
     */
    receive() external payable {}

    /**
     * @notice Creates new campaign
     * @param _title Title of the campaign
     * @param _description Description of the campaign
     * @param _image Visual representation of the campaign
     * @param _currency Currency in which the campaign is collecting funds, either ETH or DAI
     * @param _requiredSum Sum needed for the successful campaign
     */
    function createCampaign(string memory _title, string memory _description, string memory _image, Currency _currency, uint256 _requiredSum) external {
        Campaign storage campaign = campaigns[campaignsCounter];

        campaign.title = _title;
        campaign.description = _description;
        campaign.image = _image;
        campaign.currency = _currency;
        campaign.requiredSum = _requiredSum;
        campaign.status = CampaignStatus.Open;

        campaignsCounter++;

        emit CampaignCreated(campaign.title, campaign.requiredSum);
    }

    /**
     * @notice Donates ETH to the campaign
     * @dev A weird function name results in a function signature starting with 0000,
     * @dev resulting in this and donateDAI_y4Y functions being the first two functions on the list (sorted by solidity compiler)
     * @dev Saving about 200-250 gas just because of the function name (22 gas saved for each hop EVM needs to do) and every gas saved is nontrivial because donation functions are by far most frequently used by end users
     * @dev Using pool directly instead of router guarantees instant swap and less gas consumed
     * @dev If this contract would have its frontend, calculations for the amountOut should be done outside of the function through a separate view function that doesn't consume gas, resulting in cheaper protocol for end users
     * @param _campaignId Id of the campaign
     * @param _amountOutMinimumDAI Minimum amount of DAI tokens if campaign currency is DAI, ignored if campaign currency is ETH
     */
    function donateETH_uwW(uint256 _campaignId, uint256 _amountOutMinimumDAI) external payable nonReentrant {
        if (_campaignId >= campaignsCounter) {
            revert CampaignNotFound();
        }

        Campaign storage campaign = campaigns[_campaignId];

        if (campaign.status != CampaignStatus.Open) {
            revert CantDonate();
        }

        if (msg.value == 0) {
            revert CantDonateZero();
        }

        uint256 donatedAmount;

        if (campaign.currency == Currency.ETH) {
            donatedAmount = msg.value;

            campaignDonationEffects(campaign, donatedAmount);
        } else {
            uint256 amountOut = getExpectedDAIOutOfUniswapPool(msg.value);
            require(amountOut >= _amountOutMinimumDAI, "Insufficient output amount");

            donatedAmount = amountOut;

            campaignDonationEffects(campaign, donatedAmount);

            IWETH9(WETH9Address).deposit{value: msg.value}();
            require(IWETH9(WETH9Address).balanceOf(address(this)) >= msg.value, "Weth deposit fail");

            IERC20(WETH9Address).safeTransferFrom(address(this), address(uniswapPair), msg.value);

            uniswapPair.swap(amountOut, 0, address(this), new bytes(0));
        }
    }

    /**
     * @notice Donates DAI tokens to the campaign
     * @notice User should first call the DAI contract and allow this contract to spend the desired amount of tokens (if this contract were to be used with a front-end, the front-end would be the one to initiate both transactions for a better user experience)
     * @dev A weird function name results in a function signature starting with 0000,
     * @dev resulting in this and donateETH_uwW functions being the first two functions on the list (sorted by solidity compiler)
     * @dev Saving about 200-250 gas just because of the function name (22 gas saved for each hop EVM needs to do) and every gas saved is nontrivial because donation functions are by far most frequently used by end users
     * @dev Using pool directly instead of router guarantees instant swap and less gas consumed
     * @dev If this contract would have its frontend, calculations for the amountOut should be done outside of the function through a separate view function that doesn't consume gas, resulting in cheaper protocol for end users
     * @param _campaignId Id of the campaign
     * @param _amount Amount of DAI tokens
     * @param _amountOutMinimumETH Minimum ETH amount if campaign currency is ETH, ignored if campaign currency is DAI
     */
    function donateDAI_y4Y(uint256 _campaignId, uint256 _amount, uint256 _amountOutMinimumETH) external nonReentrant {
        if (_campaignId >= campaignsCounter) {
            revert CampaignNotFound();
        }

        Campaign storage campaign = campaigns[_campaignId];

        if (campaign.status != CampaignStatus.Open) {
            revert CantDonate();
        }

        if (_amount == 0) {
            revert CantDonateZero();
        }

        uint256 donatedAmount;

        if (campaign.currency == Currency.DAI) {
            donatedAmount = _amount;

            campaignDonationEffects(campaign, donatedAmount);

            if (IERC20(DAIAddress).allowance(msg.sender, address(this)) < _amount) {
                revert InsufficientAllowance();
            }

            IERC20(DAIAddress).safeTransferFrom(msg.sender, address(this), _amount);
        } else {
            uint256 amountOut = getExpectedETHOutOfUniswapPool(_amount);
            require(amountOut >= _amountOutMinimumETH, "Insufficient output amount");

            donatedAmount = amountOut;

            campaignDonationEffects(campaign, donatedAmount);

            if (IERC20(DAIAddress).allowance(msg.sender, address(this)) < _amount) {
                revert InsufficientAllowance();
            }

            IERC20(DAIAddress).safeTransferFrom(msg.sender, address(uniswapPair), _amount);

            uniswapPair.swap(0, amountOut, address(this), new bytes(0));

            IWETH9(WETH9Address).withdraw(donatedAmount);
        }
    }

    /**
     * @notice The Owner of the protocol adds the withdrawal address to the campaign
     * @param _campaignId Id of the campaign
     * @param _withdrawalAddress Address which the owner can withdraw collected funds from the campaign
     */
    function addWithdrawalAddress(uint256 _campaignId, address _withdrawalAddress) external onlyOwner {
        if (_campaignId >= campaignsCounter) {
            revert CampaignNotFound();
        }

        if (
            campaigns[_campaignId].status != CampaignStatus.WaitingAdminAction
        ) {
            revert WrongCampaignStatus();
        }

        campaigns[_campaignId].withdrawalAddress = _withdrawalAddress;
        campaigns[_campaignId].status = CampaignStatus.WaitingWithdrawal;
    }

    /**
     * @notice Owner of the protocol changes campaign status to Closed
     * @param _campaignId Id of the campaign
     * @param _withdrawalAddress Address which the owner can withdraw collected funds from the campaign
     */
    function setCampaignStatusToClosed(uint256 _campaignId, address _withdrawalAddress) external onlyOwner {
        if (_campaignId >= campaignsCounter) {
            revert CampaignNotFound();
        }

        if (campaigns[_campaignId].status != CampaignStatus.Open) {
            revert WrongCampaignStatus();
        }

        campaigns[_campaignId].withdrawalAddress = _withdrawalAddress;
        campaigns[_campaignId].status = CampaignStatus.Closed;
    }

    /**
     * @notice Owner of the protocol changes campaign status to Open
     * @param _campaignId Id of the campaign
     */
    function setCampaignStatusToOpen(uint256 _campaignId) external onlyOwner {
        if (_campaignId >= campaignsCounter) {
            revert CampaignNotFound();
        }

        if (campaigns[_campaignId].status != CampaignStatus.Closed) {
            revert WrongCampaignStatus();
        }

        campaigns[_campaignId].withdrawalAddress = address(0);
        campaigns[_campaignId].status = CampaignStatus.Open;
    }

    /**
     * @notice Owner of approved address withdraws funds from the finished campaign
     * @param _campaignId Id of the campaign
     */
    function withdraw(uint256 _campaignId) external payable {
        Campaign storage campaign = campaigns[_campaignId];

        if (
            campaign.status == CampaignStatus.Successful ||
            campaign.withdrawalAddress != msg.sender ||
            (campaign.status != CampaignStatus.WaitingWithdrawal && campaign.status != CampaignStatus.Closed)
        ) {
            revert CantWithdraw();
        }

        campaign.status = CampaignStatus.Successful;

        if (campaign.currency == Currency.ETH) {
            (bool sent, ) = msg.sender.call{value: campaign.collectedSum}("");
            require(sent, "Failed to send");
        }
        else {
            IERC20(DAIAddress).safeTransferFrom(address(this), msg.sender, campaign.collectedSum);
        }

        emit Withdrawn(campaign.title, msg.sender, campaign.collectedSum);
    }

    /**
     * @notice Gets the list of all donors and the amount they donated to the campaign
     * @param _campaignId Id of the campaign
     */
    function getDonators(uint256 _campaignId) external view returns (address[] memory, uint256[] memory) {
        return (
            campaigns[_campaignId].donatorsAdresses,
            campaigns[_campaignId].donatorsAmounts
        );
    }

    /**
     * @notice Gets the list of all campaigns
     */
    function getCampaigns() external view returns (Campaign[] memory) {
        Campaign[] memory allCampaigns = new Campaign[](campaignsCounter);

        for (uint256 i = 0; i < campaignsCounter; i++) {
            allCampaigns[i] = campaigns[i];
        }

        return allCampaigns;
    }

    /**
     * @notice Gets the expected amount of DAI tokens out of the DAI-WETH Uniswap V2 pool
     * @param _amountInWETH Amount of WETH tokens sent into the pool
     */
    function getExpectedDAIOutOfUniswapPool(uint256 _amountInWETH) public view returns (uint256 amountOut) {
        (uint256 reserveOut, uint256 reserveIn, ) = uniswapPair.getReserves();
        amountOut = (reserveOut * ((_amountInWETH * 997) / 1000)) / (reserveIn + ((_amountInWETH * 997) / 1000));
    }

    /**
     * @notice Gets the expected amount of WETH tokens out of the DAI-WETH Uniswap V2 pool
     * @param _amountInDAI Amount of DAI tokens sent into the pool
     */
    function getExpectedETHOutOfUniswapPool(uint256 _amountInDAI) public view returns (uint256 amountOut) {
        (uint256 reserveIn, uint256 reserveOut, ) = uniswapPair.getReserves();
        amountOut = (reserveOut * ((_amountInDAI * 997) / 1000)) / (reserveIn + ((_amountInDAI * 997) / 1000));
    }

    /**
     * @notice Disables renounceOwnership() function from the imported OZ's Ownable2Step contract
     */
    function renounceOwnership() public override {}

    /**
     * @notice Updates campaign data
     * @param _campaign Campaign that will be updated
     * @param _donatedAmount Amount donated to the campaign, in the currency that the campaign specified
     */
    function campaignDonationEffects(Campaign storage _campaign, uint256 _donatedAmount) internal {
            _campaign.collectedSum += _donatedAmount;

            _campaign.donatorsAdresses.push(msg.sender);
            _campaign.donatorsAmounts.push(_donatedAmount);

            emit Donated(msg.sender, _donatedAmount, _campaign.title);

            if (_campaign.collectedSum >= _campaign.requiredSum) {
                _campaign.status = CampaignStatus.WaitingAdminAction;

                emit WaitingAdminAction(_campaign.title);
            }
    }
}