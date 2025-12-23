//SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

//we are pooling stake for datapoints(same)
//giving loser's stake as to the highest bonders(in the pool)
contract OracleDisputeSystem{
    error ODS_RequiresMoreBond();
    error ODS_DataPointAlreadyFinalized();
    error ODS_DataPointNotFinalized();
    error ODS_NoDataPointSubmitted();
    error ODS_TimeOutHasNotOccured();
    error ODS_UserHasAlreadyWithdrawn();
    error ODS_NotWinner();
    error ODS_CallFailure();
    error ODS_TimeOutHasAlreadyOccured();
    error ODS_WithdrawalPeriodExpired();
    error ODS_NotOwner();
    error ODS_WithdrawalPeriodHasNotExpired();
    error ODS_NothingToClaim();

    uint256 public constant MIN_BOND = 0.001 ether;
    uint256 public constant TIMEOUT = 1 days;
    uint256 public constant WITHRAWAL_PERIOD = 30 days;
    address public immutable i_owner;

    struct DataPoint{
        bytes32 dataPoint;
        uint256 highestBond;
        uint256 deadline;
        bool finalized;
    }

    //as there are questionId implementing multiple questions in an oracle, which is a great thing, should there be a function to post questions???

    mapping(bytes32 questionId => DataPoint) public dataPoints; //??
    mapping(bytes32 questionId => uint256 escrow) public totalEscrow;
    
    //pooling additions
    mapping(bytes32 questionId => mapping(bytes32 dataPoint => uint256 bond)) public pooledBond;
    mapping(bytes32 questionId => mapping(address bonder => mapping(bytes32 dataPoint => uint256 bond))) public userBond;
    mapping(bytes32 questionId => mapping(address bonder => bool)) public hasWithdrawn;

    event DataPointSubmitted(bytes32 indexed questionId, address indexed bonder, bytes32 dataPoint, uint256 bond);
    event DataPointFinalized(bytes32 indexed questionId, bytes32 dataPoint, uint256 bond);
    event Withdrawn(bytes32 indexed questionId, address indexed bonder, uint256 payOut);

    constructor(){
        i_owner = msg.sender;
    }

    //create a function to createQuestions too!!!!!!!!????????

    function postValue(bytes32 questionId, bytes32 dataPoint) external payable{
        if(msg.value < MIN_BOND){
            revert ODS_RequiresMoreBond();
        }

        DataPoint storage dp = dataPoints[questionId];

        if(dp.finalized){
            revert ODS_DataPointAlreadyFinalized();
        }    

        if(dp.deadline == 0){
            dp.deadline = block.timestamp + TIMEOUT;
        } else {
            if(block.timestamp >= dp.deadline){
                revert ODS_TimeOutHasAlreadyOccured();
            }
        }

        uint256 newTotalForDataPoint = pooledBond[questionId][dataPoint] + msg.value;

        if(dataPoint != dp.dataPoint && newTotalForDataPoint <= dp.highestBond){
            revert ODS_RequiresMoreBond();
        }

        pooledBond[questionId][dataPoint] += msg.value;
        userBond[questionId][msg.sender][dataPoint] += msg.value;
        totalEscrow[questionId] += msg.value;

        if(newTotalForDataPoint > dp.highestBond){
            dp.highestBond = newTotalForDataPoint;
            dp.dataPoint = dataPoint;
        }

        emit DataPointSubmitted(questionId, msg.sender, dataPoint, msg.value);
    }

    //automate this with chainlink automation 
    function finalizeData(bytes32 questionId) external{
        DataPoint storage dp = dataPoints[questionId];

        if (dp.finalized){
            revert ODS_DataPointAlreadyFinalized();
        }

        if (dp.highestBond == 0){
            revert ODS_NoDataPointSubmitted();
        }

        if(block.timestamp < dp.deadline){
            revert ODS_TimeOutHasNotOccured();
        }

        dp.finalized = true;

        emit DataPointFinalized(questionId, dp.dataPoint, dp.highestBond);
    }

    function withdraw(bytes32 questionId) external{
        DataPoint storage dp = dataPoints[questionId];

        if(!dp.finalized){
            revert ODS_DataPointNotFinalized();
        }

        if(hasWithdrawn[questionId][msg.sender]){
            revert ODS_UserHasAlreadyWithdrawn();
        }

        if(block.timestamp > dp.deadline + WITHRAWAL_PERIOD){
            revert ODS_WithdrawalPeriodExpired();
        }

        bytes32 winningDataPoint = dp.dataPoint;
        uint256 userStake = userBond[questionId][msg.sender][winningDataPoint];

        if(userStake == 0){
            revert ODS_NotWinner();
        }

        hasWithdrawn[questionId][msg.sender] = true;
        userBond[questionId][msg.sender][winningDataPoint] = 0;

        uint256 loserPool = totalEscrow[questionId] - dp.highestBond;
        uint256 payOut = userStake;

        if(loserPool > 0 && dp.highestBond > 0){
            payOut += (userStake * loserPool) / dp.highestBond; // alice: 10; bob: 08; winning pool bond: 18; loosing pool bond: 08 --> alice: (10*08)/18 = 4.44 + 10 eth ; bob: (08*08)/18 = 3.555 + 08 eth
        }

        totalEscrow[questionId] -= payOut;
        dp.highestBond -= userStake;
        
        (bool callSuccess, ) = msg.sender.call{value: payOut}("");
        if(!callSuccess){
            revert ODS_CallFailure();
        }

        emit Withdrawn(questionId, msg.sender, payOut);
    }

    function recoverUnclaimed(bytes32 questionId) external{
        if(msg.sender != i_owner){
            revert ODS_NotOwner();
        }

        DataPoint storage dp = dataPoints[questionId];

        if(!dp.finalized){
            revert ODS_DataPointNotFinalized();
        }

        if(block.timestamp < dp.deadline + WITHRAWAL_PERIOD){
            revert ODS_WithdrawalPeriodHasNotExpired();
        }

        if(address(this).balance == 0){
            revert ODS_NothingToClaim();
        }

        (bool callSuccess, ) = msg.sender.call{value: totalEscrow[questionId]}("");

        if(!callSuccess){
            revert ODS_CallFailure();
        }
    }

    function getTotalEscrow(bytes32 questionId) public view returns(uint256){
        return totalEscrow[questionId];
    }

    function getPooledBond(bytes32 questionId, bytes32 dataPoint) public view returns(uint256){
        return pooledBond[questionId][dataPoint];
    }

    function getUserBond(bytes32 questionId, address bonder, bytes32 dataPoint) public view returns(uint256){
        return userBond[questionId][bonder][dataPoint];
    }

    function getCurrentHighestVotedForDataPoint(bytes32 questionId) public view returns(DataPoint memory){
        return dataPoints[questionId];
    }

    function getOwner() public view returns(address){
        return i_owner;
    }
}