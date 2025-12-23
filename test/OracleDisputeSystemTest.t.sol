//SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test, console} from 'forge-std/Test.sol';
import {OracleDisputeSystem} from '../src/OracleDisputeSystem.sol';
import {DeployODS} from '../script/DeployODS.s.sol';

contract OracleDisputeSystemTest is Test{
    OracleDisputeSystem public ods;
    DeployODS public deployer;

    address public phil = makeAddr("phil");
    address public claire = makeAddr("claire");
    address public luke = makeAddr("luke");
    uint256 public timeout = 1 days;
    uint256 public withdrawal_period = 30 days;

    event DataPointSubmitted(bytes32 indexed questionId, address indexed bonder, bytes32 dataPoint, uint256 bond);
    event DataPointFinalized(bytes32 indexed questionId, bytes32 dataPoint, uint256 bond);
    event Withdrawn(bytes32 indexed questionId, address indexed bonder, uint256 payOut);

    function setUp() external{
        deployer = new DeployODS();
        (ods) = deployer.run();

        vm.deal(phil, 10e18);
        vm.deal(claire, 10e18);
        vm.deal(luke, 10e18);
    }

    modifier valuePosted(){
        vm.prank(phil);
        ods.postValue{value: 1e18}(0, 0);
        _;
    }

    function testPostValueRevertsWhenBondIsLesser() public{
        vm.prank(phil);
        vm.expectRevert(OracleDisputeSystem.ODS_RequiresMoreBond.selector);
        ods.postValue{value: 0}(0, 0);
    }

    function testPostValueRevertsWhenTimeOutHasOccured() public{
        vm.prank(phil);
        ods.postValue{value: 1e18}(0, 0);

        vm.warp(block.timestamp + timeout + 1);

        vm.prank(claire);
        vm.expectRevert(OracleDisputeSystem.ODS_TimeOutHasAlreadyOccured.selector);
        ods.postValue{value: 1e18}(0, 0);
    }

    function testPostValueUpdatesDataStructures() public valuePosted{
        assert(ods.getTotalEscrow(0) == 1e18);
        assert(ods.getPooledBond(0, 0) == 1e18);
        assert(ods.getUserBond(0, phil, 0) == 1e18);
    }

    function testMultiplePostValueUpdatesDataStructures() public{
        vm.prank(phil);
        ods.postValue{value: 1e18}(0, "no");

        vm.prank(claire);
        ods.postValue{value: 2e18}(0, "yes");

        assert(ods.getTotalEscrow(0) == 3e18);

        OracleDisputeSystem.DataPoint memory dp = ods.getCurrentHighestVotedForDataPoint(0);
        assert(dp.dataPoint == "yes");
        assert(dp.highestBond == 2e18);
        assert(dp.finalized == false);
    }

    function testEventIsEmittedWhenValueIsPosted() public{
        vm.prank(phil);
        vm.expectEmit(true, true, false, false, address(ods));
        emit DataPointSubmitted(0, phil, 0, 1e18);
        ods.postValue{value: 1e18}(0, 0);
    }

    function testCannotFinalizeDataPointBeforeTimeout() public valuePosted{
        vm.prank(phil);
        vm.expectRevert(OracleDisputeSystem.ODS_TimeOutHasNotOccured.selector);
        ods.finalizeData(0);
    }

    function testCanFinalizeDataPointAfterTimeout() public valuePosted{
        vm.warp(block.timestamp + timeout + 1);
        vm.prank(phil);
        ods.finalizeData(0);
    }

    modifier Finalized(){
        vm.warp(block.timestamp + timeout + 1);
        vm.prank(phil);
        ods.finalizeData(0);
        _;
    }

    function testCannotPostValueAfterDatapointIsFinalized() public valuePosted Finalized{
        vm.prank(claire);
        vm.expectRevert(OracleDisputeSystem.ODS_DataPointAlreadyFinalized.selector);
        ods.postValue{value: 1e18}(0, "yes");
    }

    function testCannotWithdrawIfYouLost() public{
        vm.prank(phil);
        ods.postValue{value: 1e18}(0, "no");

        vm.prank(claire);
        ods.postValue{value: 2e18}(0, "yes");

        vm.warp(block.timestamp + timeout + 1);
        vm.prank(phil);
        ods.finalizeData(0);

        vm.prank(phil);
        vm.expectRevert();
        ods.withdraw(0);

        assert(ods.getTotalEscrow(0) == 3e18);
    }

    function testCanWithdrawIfYourDataPointWasFinalized() public{
        vm.prank(phil);
        ods.postValue{value: 1e18}(0, "no");

        vm.prank(claire);
        ods.postValue{value: 2e18}(0, "yes");

        vm.warp(block.timestamp + timeout + 1);
        vm.prank(phil);
        ods.finalizeData(0);

        vm.prank(claire);
        ods.withdraw(0);

        assert(ods.getTotalEscrow(0) == 0);
    }

    function testCanWithdrawWithMultipleFunders() public{
        //uint256 philInitialBalance = address(phil).balance;
        uint256 claireInitialBalance = address(claire).balance;
        //uint256 lukeInitialBalance = address(luke).balance;

        vm.prank(phil);
        ods.postValue{value: 1e18}("question1", "no");

        vm.prank(claire);
        ods.postValue{value: 2e18}("question1", "yes");

        vm.prank(luke);
        ods.postValue{value: 2e18}("question1", "yes");

        vm.warp(block.timestamp + timeout + 1);
        vm.prank(phil);
        ods.finalizeData("question1");

        vm.prank(phil);
        vm.expectRevert(OracleDisputeSystem.ODS_NotWinner.selector);
        ods.withdraw("question1");

        vm.prank(claire);
        ods.withdraw("question1");

        vm.prank(luke);
        ods.withdraw("question1");

        assert((address(claire).balance - claireInitialBalance) < 2.4e18);
        assert((address(claire).balance - claireInitialBalance) < (2e18 + ((2e18 * 1e18)/4e18)));
    }

    function testCanRecoverUnclaimedAfterWithdrawalPeriod() public valuePosted Finalized {
        address owner = ods.getOwner();
        uint256 ownerInitialBalance = address(owner).balance;

        vm.warp(block.timestamp + timeout + 1);
        vm.prank(owner);
        vm.expectRevert(OracleDisputeSystem.ODS_WithdrawalPeriodHasNotExpired.selector);
        ods.recoverUnclaimed(0);

        vm.warp(block.timestamp + timeout + withdrawal_period + 1);
        vm.prank(owner);
        ods.recoverUnclaimed(0);

        assert((address(owner).balance - ownerInitialBalance) == 1e18);
    }
}