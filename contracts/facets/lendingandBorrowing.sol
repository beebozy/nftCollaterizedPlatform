// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract Lending is ReentrancyGuard {
    using SafeMath for uint256;

    

    event LoanIssued(uint256 loanId, address indexed borrower, uint256 amount, uint256 endTime);
    event LoanRepaid(uint256 loanId, address indexed borrower, uint256 interestPaid);
    event NFTDeposited(address indexed borrower, uint256 tokenId, address tokenAddress);
    event FundsClaimed(address indexed lender, uint256 amount);

    // Deposit NFT as collateral
    function depositNFT(address nftContractAddress, uint256 tokenId) external {
        IERC721 nftContract = IERC721(nftContractAddress);
        require(nftContract.ownerOf(tokenId) == msg.sender, "Not the owner of the NFT");

        nftContract.transferFrom(msg.sender, address(this), tokenId);
        emit NFTDeposited(msg.sender, tokenId, nftContractAddress);
    }

    // Allow anyone to deposit funds for lending purposes
    function depositFunds() external payable {
        require(msg.value > 0, "Deposit amount must be greater than zero");
        lenderBalances[msg.sender] = lenderBalances[msg.sender].add(msg.value);
    }

    // Borrow function for collateral-backed loans
    function borrow(uint256 amount, address nftContractAddress, uint256 tokenId, uint256 duration) external nonReentrant {
        require(duration >= MIN_LOAN_DURATION && duration <= MAX_LOAN_DURATION, "Invalid loan duration");
        IERC721 nftContract = IERC721(nftContractAddress);
        require(nftContract.ownerOf(tokenId) == msg.sender, "You must own the NFT as collateral");

        nftContract.transferFrom(msg.sender, address(this), tokenId);

        loans[nextLoanId] = Loan({
            borrower: msg.sender,
            amount: amount,
            startTime: block.timestamp,
            endTime: block.timestamp + duration,
            collateralTokenId: tokenId,
            collateralTokenAddress: nftContractAddress,
            repaid: false
        });
        nextLoanId++;

        // Transfer loan amount to borrower
        payable(msg.sender).transfer(amount);
        emit LoanIssued(nextLoanId - 1, msg.sender, amount, block.timestamp + duration);
    }

    // Calculate interest based on amount and loan duration
    function calculateInterest(uint256 principal, uint256 duration) public pure returns (uint256) {
        return principal.mul(INTEREST_RATE).mul(duration).div(100).div(365 days);
    }

    // Repay loan function, paying principal and interest
    function repayLoan(uint256 loanId) external payable nonReentrant {
        Loan storage loan = loans[loanId];
        require(msg.sender == loan.borrower, "You are not the borrower");
        require(!loan.repaid, "Loan has already been repaid");
        require(block.timestamp <= loan.endTime, "Loan term has expired");

        uint256 interest = calculateInterest(loan.amount, loan.endTime - loan.startTime);
        uint256 totalRepayment = loan.amount.add(interest);
        require(msg.value >= totalRepayment, "Repayment amount too low");

        loan.repaid = true;

        // Return NFT collateral to borrower
        IERC721 nftContract = IERC721(loan.collateralTokenAddress);
        nftContract.transferFrom(address(this), loan.borrower, loan.collateralTokenId);

        // Accrue repayment with interest to the lender's balance
        lenderBalances[address(this)] = lenderBalances[address(this)].add(totalRepayment);
        emit LoanRepaid(loanId, msg.sender, interest);
    }

    // Lenders can claim their balance, which includes original deposits and any interest accrued
    function claimFunds() external nonReentrant {
        uint256 amount = lenderBalances[msg.sender];
        require(amount > 0, "No funds available for claiming");

        lenderBalances[msg.sender] = 0;
        payable(msg.sender).transfer(amount);
        emit FundsClaimed(msg.sender, amount);
    }

    // Check contract's Ether balance
    function getContractBalance() external view returns (uint256) {
        return address(this).balance;
    }
}
