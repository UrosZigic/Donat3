//SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/Donat3.sol";
import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract Donat3Test is Test {

    Donat3 public donat3;
    address admin = address(123);
    address otherUser = address(45678);
    IERC20 public dai;

    event CampaignCreated(string indexed title, uint256 indexed requiredSum);
    event Donated(address indexed donator, uint256 indexed amount, string indexed title);
    event WaitingAdminAction(string indexed title);
    event Withdrawn(string indexed title, address indexed withdrawalAddress, uint256 indexed collectedSum);


    function setUp() public {
        donat3 = new Donat3(admin, 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f, 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2, 0x6B175474E89094C44Da98b954EedeAC495271d0F);
        dai = IERC20(donat3.DAIAddress());
    }

    function testCreateCampaign() public {
        vm.expectEmit(true, true, false, false);
        emit CampaignCreated("campaign1", 200 ether);

        vm.prank(admin);
        donat3.createCampaign("campaign1", "description1", "imageLink1", Donat3.Currency.DAI, 200 ether);

        assertEq(donat3.campaignsCounter(), 1);

        (string memory title, string memory description, string memory image, Donat3.Currency currency, uint256 requiredSum,,,) = donat3.campaigns(0);
        assertEq(title, "campaign1");
        assertEq(description, "description1");
        assertEq(image, "imageLink1");
        assertEq(uint256(currency), uint256(Donat3.Currency.DAI));
        assertEq(requiredSum, 200 ether);
    }

    function testDonateETHToETHCampaign() public {
        vm.startPrank(admin);
        donat3.createCampaign("campaign1", "description1", "imageLink1", Donat3.Currency.ETH, 1 ether);
        
        vm.expectEmit(true, true, true, false);
        emit Donated(admin, 1 ether, "campaign1");

        vm.expectEmit(true, false, false, false);
        emit WaitingAdminAction("campaign1");

        vm.deal(admin, 1 ether);
        donat3.donateETH_uwW{value: 1 ether}(0, 0);

        (,,,,, uint256 collectedSum,, Donat3.CampaignStatus status) = donat3.campaigns(0);
        assertEq(collectedSum, 1 ether);
        assertEq(uint256(status), uint256(Donat3.CampaignStatus.WaitingAdminAction));
    }

    function testDonateETHToDAICampaign() public {
        vm.startPrank(admin);
        donat3.createCampaign("campaign1", "description1", "imageLink1", Donat3.Currency.DAI, 500*10**18);

        uint256 DAIAmount = donat3.getExpectedDAIOutOfUniswapPool(1 ether);

        vm.expectEmit(true, true, true, false);
        emit Donated(admin, DAIAmount, "campaign1");

        vm.expectEmit(true, false, false, false);
        emit WaitingAdminAction("campaign1");

        vm.deal(admin, 1 ether);
        donat3.donateETH_uwW{value: 1 ether}(0, 0);

        (,,,,, uint256 collectedSum,, Donat3.CampaignStatus status) = donat3.campaigns(0);
        assertEq(collectedSum, DAIAmount);
        assertEq(uint256(status), uint256(Donat3.CampaignStatus.WaitingAdminAction));
    }

    function testDonateDAIToDAICampaign() public {
        vm.startPrank(admin);
        donat3.createCampaign("campaign1", "description1", "imageLink1", Donat3.Currency.DAI, 500*10**18);

        deal(address(dai), admin, 500*10**18, true);
        dai.approve(address(donat3), 500*10**18);

        vm.expectEmit(true, true, true, false);
        emit Donated(admin, 500*10**18, "campaign1");

        vm.expectEmit(true, false, false, false);
        emit WaitingAdminAction("campaign1");

        donat3.donateDAI_y4Y(0, 500*10**18, 0);

        (,,,,, uint256 collectedSum,, Donat3.CampaignStatus status) = donat3.campaigns(0);
        assertEq(collectedSum, 500*10**18);
        assertEq(uint256(status), uint256(Donat3.CampaignStatus.WaitingAdminAction));
    }

    function testDonateDAIToETHCampaign() public {
        vm.startPrank(admin);
        donat3.createCampaign("campaign1", "description1", "imageLink1", Donat3.Currency.ETH, 1 ether);

        deal(address(dai), admin, 3000*10**18, true);
        dai.approve(address(donat3), 3000*10**18);

        uint256 ETHAmount = donat3.getExpectedETHOutOfUniswapPool(3000*10**18);

        vm.expectEmit(true, true, true, false);
        emit Donated(admin, ETHAmount, "campaign1");

        vm.expectEmit(true, false, false, false);
        emit WaitingAdminAction("campaign1");

        donat3.donateDAI_y4Y(0, 3000*10**18, 0);

        (,,,,, uint256 collectedSum,, Donat3.CampaignStatus status) = donat3.campaigns(0);
        assertEq(collectedSum, ETHAmount);
        assertEq(uint256(status), uint256(Donat3.CampaignStatus.WaitingAdminAction));
    }

    function testAddingWithdrawalAddress() public {
        vm.startPrank(admin);
        donat3.createCampaign("campaign1", "description1", "imageLink1", Donat3.Currency.ETH, 1 ether);

        vm.deal(admin, 1 ether);
        donat3.donateETH_uwW{value: 1 ether}(0, 0);

        (,,,,,,, Donat3.CampaignStatus status) = donat3.campaigns(0);
        assertEq(uint256(status), uint256(Donat3.CampaignStatus.WaitingAdminAction));

        donat3.addWithdrawalAddress(0, admin);

        (,,,,,, address withdrawalAddress, Donat3.CampaignStatus status1) = donat3.campaigns(0);
        assertEq(withdrawalAddress, admin);
        assertEq(uint256(status1), uint256(Donat3.CampaignStatus.WaitingWithdrawal));
    }

    function testSettingStatusToClosed() public {
        vm.startPrank(admin);
        donat3.createCampaign("campaign1", "description1", "imageLink1", Donat3.Currency.ETH, 1 ether);

        (,,,,,,, Donat3.CampaignStatus status) = donat3.campaigns(0);
        assertEq(uint256(status), uint256(Donat3.CampaignStatus.Open));

        donat3.setCampaignStatusToClosed(0, admin);

        (,,,,,, address withdrawalAddress, Donat3.CampaignStatus status1) = donat3.campaigns(0);
        assertEq(withdrawalAddress, admin);
        assertEq(uint256(status1), uint256(Donat3.CampaignStatus.Closed));
    }

    function testSettingStatusToOpen() public {
        vm.startPrank(admin);
        donat3.createCampaign("campaign1", "description1", "imageLink1", Donat3.Currency.ETH, 1 ether);

        donat3.setCampaignStatusToClosed(0, admin);
        
        (,,,,,,, Donat3.CampaignStatus status) = donat3.campaigns(0);
        assertEq(uint256(status), uint256(Donat3.CampaignStatus.Closed));

        donat3.setCampaignStatusToOpen(0);

        (,,,,,, address withdrawalAddress, Donat3.CampaignStatus status1) = donat3.campaigns(0);
        assertEq(withdrawalAddress, address(0));
        assertEq(uint256(status1), uint256(Donat3.CampaignStatus.Open));
    }

    function testWithdrawalOfETHCampaign() public {
        vm.startPrank(admin);
        donat3.createCampaign("campaign1", "description1", "imageLink1", Donat3.Currency.ETH, 1 ether);
        
        vm.deal(admin, 1 ether);
        donat3.donateETH_uwW{value: 1 ether}(0, 0);

        donat3.addWithdrawalAddress(0, admin);

        (,,,,, uint256 collectedSum,,) = donat3.campaigns(0);

        uint256 balanceBefore = address(admin).balance;

        vm.expectEmit(true, true, true, false);
        emit Withdrawn("campaign1", admin, collectedSum);
        
        donat3.withdraw(0);

        uint256 balanceAfter = address(admin).balance;

        assertEq(balanceAfter - balanceBefore, collectedSum);

        (,,,,,,, Donat3.CampaignStatus status) = donat3.campaigns(0);
        assertEq(uint256(status), uint256(Donat3.CampaignStatus.Successful));
    }

    function testWithdrawalOfDAICampaign() public {
        vm.startPrank(admin);
        donat3.createCampaign("campaign1", "description1", "imageLink1", Donat3.Currency.DAI, 500*10**18);
        
        deal(address(dai), admin, 500*10**18, true);
        dai.approve(address(donat3), 500*10**18);
        donat3.donateDAI_y4Y(0, 500*10**18, 0);

        donat3.addWithdrawalAddress(0, admin);

        (,,,,, uint256 collectedSum,,) = donat3.campaigns(0);

        uint256 balanceBefore = dai.balanceOf(admin);

        vm.expectEmit(true, true, true, false);
        emit Withdrawn("campaign1", admin, collectedSum);
        
        donat3.withdraw(0);

        uint256 balanceAfter = dai.balanceOf(admin);

        assertEq(balanceAfter - balanceBefore, collectedSum);

        (,,,,,,, Donat3.CampaignStatus status) = donat3.campaigns(0);
        assertEq(uint256(status), uint256(Donat3.CampaignStatus.Successful));
    }

    function testFailWithdrawal() public {
        vm.startPrank(admin);
        donat3.createCampaign("campaign1", "description1", "imageLink1", Donat3.Currency.ETH, 1 ether);
        
        vm.deal(admin, 1 ether);
        donat3.donateETH_uwW{value: 1 ether}(0, 0);

        donat3.addWithdrawalAddress(0, otherUser);
        
        donat3.withdraw(0);
    }
}