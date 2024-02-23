// SPDX-License-Identifier: MIT

// version
pragma solidity ^0.8.0;

// imports
import {VRFCoordinatorV2Interface} from "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import {VRFConsumerBaseV2} from "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";

/**
 * @title Florida Raffle Lottery
 * @author Landon Johnson
 * @notice This contract is a simple raffle lottery contract that allows users to purchase tickets and win a prize.
 * @dev This contract implements Chainlink VRF to generate random numbers for the raffle.
 */

contract Raffle is VRFConsumerBaseV2 {
    // errors
    error Raffle__NotEnoughEthSent();
    error Raffle__SendMoreToEnterRaffle();
    error Raffle_TransferFailed();
    error Raffle__RaffleNotOpen();
    error Raffle__UpkeepNotNeeded(
        uint256 currentBalance,
        uint256 numPayers,
        uint256 raffleState
    );

    /* Type declarations */
    enum RaffleState {
        OPEN,
        CALCULATING
    }

    // State variables
    address public manager;

    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private constant NUM_WORDS = 1;

    VRFCoordinatorV2Interface private immutable i_vrfCoordinator;
    bytes32 private immutable i_gasLane;
    uint64 private immutable i_subscriptionId;
    uint256 private immutable i_ticketPrice;
    uint32 private immutable i_callbackGasLimit;
    //@dev interval is the time between raffles in seconds
    uint256 private immutable i_interval;
    ///////////////////////////////////////
    address payable[] private s_players;
    uint256 private s_lastTimeStamp;
    address private s_recentWinner;
    RaffleState private s_raffleState;

    //Events
    event EnteredRaffle(address indexed player);
    event PickedWinner(address indexed winner);
    event RequestedRaffleWinner(uint256 indexed requestId);

    constructor(
        uint256 ticketPrice,
        uint256 interval,
        address vrfCoordinator,
        bytes32 gasLane,
        uint64 subscriptionId,
        uint32 callbackGasLimit
    ) VRFConsumerBaseV2(vrfCoordinator) {
        i_ticketPrice = ticketPrice;
        i_interval = interval;
        s_lastTimeStamp = block.timestamp;
        i_vrfCoordinator = VRFCoordinatorV2Interface(vrfCoordinator);
        i_gasLane = gasLane;
        i_subscriptionId = subscriptionId;
        i_callbackGasLimit = callbackGasLimit;
        s_raffleState = RaffleState.OPEN;
    }

    // Functions
    function enterRaffle() external payable {
        if (msg.value < i_ticketPrice) {
            revert Raffle__NotEnoughEthSent();
        }
        if (s_raffleState != RaffleState.OPEN) {
            revert Raffle__RaffleNotOpen();
        }
        s_players.push(payable(msg.sender));
        // 1. Makes migration easier
        // 2. Makes front-end "indexing" easier
        emit EnteredRaffle(msg.sender);
    }

    // When is the winner suposed to be picked?
    /**
     *
     * @dev This function is used to check if the contract needs to call
     * an upkeep function. It returns true if the contract needs to call
     * 1. The time interval has passed betwwen raffle runs
     * 2. The raffle is in the OPEN state
     * 3. The contract has enough LINK to pay for the VRF request
     * 4. The contract has enough ETH (aka, Players have paid for tickets)
     */
    function checkUpkeep(
        bytes memory /* checkData */
    ) public view returns (bool upkeepNeeded, bytes memory /*performData*/) {
        bool timeHasPassed = (block.timestamp - s_lastTimeStamp) >= i_interval;
        bool isOpen = s_raffleState == RaffleState.OPEN;
        bool hasbalance = address(this).balance >= 0;
        bool hasPlayers = s_players.length > 0;
        upkeepNeeded = (timeHasPassed && isOpen && hasbalance && hasPlayers);
        return (upkeepNeeded, "0x0");
    }

    // 2. Use that number to pick a winner
    // 3. Transfer the prize to the winner automatically
    function performUpkeep(bytes calldata /*performData*/) external {
        (bool upkeepNeeded, ) = checkUpkeep("");
        if (!upkeepNeeded) {
            revert Raffle__UpkeepNotNeeded(
                address(this).balance,
                s_players.length,
                uint256(s_raffleState)
            );
        }
        s_raffleState = RaffleState.CALCULATING;
        // 1. Get a random number from Chainlink VRF
        uint256 requestId = i_vrfCoordinator.requestRandomWords(
            i_gasLane, // gas lane
            i_subscriptionId, // Funded Id
            REQUEST_CONFIRMATIONS, //Number of block satified confirmations
            i_callbackGasLimit, // for overspending on gas
            NUM_WORDS // number of random numbers
        );
        emit RequestedRaffleWinner(requestId);
    }

    // CEI: Check-Effect-Interact
    function fulfillRandomWords(
        uint256 /*requestId*/,
        uint256[] memory randomWords
    ) internal override {
        uint256 indexOfWinner = randomWords[0] % s_players.length;
        address payable winner = s_players[indexOfWinner];
        s_recentWinner = winner;
        s_raffleState = RaffleState.OPEN;
        s_players = new address payable[](0);
        s_lastTimeStamp = block.timestamp;
        emit PickedWinner(winner);

        (bool success, ) = winner.call{value: address(this).balance}("");
        if (!success) {
            revert Raffle_TransferFailed();
        }
    }

    /*getters*/
    function getTicketPrice() external view returns (uint256) {
        return i_ticketPrice;
    }

    function getRaffleState() external view returns (RaffleState) {
        return s_raffleState;
    }

    function getPlayer(uint256 indexOfPlayers) external view returns (address) {
        return s_players[indexOfPlayers];
    }

    function getLastTimeStamp() external view returns (uint256) {
        return s_lastTimeStamp;
    }

    function getRecentWinner() external view returns (address) {
        return s_recentWinner;
    }

    function getLengthOfPlayers() external view returns (uint256) {
        return s_players.length;
    }
}
