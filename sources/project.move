module send_message::simple_lending {
    use std::error;
    use std::signer;
    use aptos_framework::coin::{Self, Coin};
    use aptos_framework::timestamp;
    use aptos_std::table::{Self, Table};

    /// Error codes
    const E_LOAN_NOT_FOUND: u64 = 1;
    const E_LOAN_ALREADY_FUNDED: u64 = 2;
    const E_UNAUTHORIZED: u64 = 3;
    const E_INVALID_LOAN_TERMS: u64 = 4;

    /// Loan status
    const LOAN_STATUS_PENDING: u8 = 0;
    const LOAN_STATUS_ACTIVE: u8 = 1;

    /// Resource struct to store all loans in the protocol
    struct LendingProtocol has key {
        loans: Table<u64, LoanInfo>,
        next_loan_id: u64,
    }

    /// Struct to store loan information
    struct LoanInfo has store, drop {
        loan_id: u64,
        borrower: address,
        lender: address,
        loan_amount: u64,
        interest_rate: u64,  // basis points (1/100 of a percent)
        term_in_seconds: u64,
        created_at: u64,
        status: u8,
    }

    /// Initialize the lending protocol
    fun init_module(admin: &signer) {
        let admin_addr = signer::address_of(admin);
        
        move_to(admin, LendingProtocol {
            loans: table::new(),
            next_loan_id: 0,
        });
    }

    /// Create a loan request
    public entry fun create_loan_request<CoinType>(
        borrower: &signer,
        loan_amount: u64,
        interest_rate: u64,
        term_in_seconds: u64
    ) acquires LendingProtocol {
        // Validate loan parameters
        assert!(loan_amount > 0, error::invalid_argument(E_INVALID_LOAN_TERMS));
        assert!(term_in_seconds > 0, error::invalid_argument(E_INVALID_LOAN_TERMS));
        
        let borrower_addr = signer::address_of(borrower);
        
        // Get lending protocol
        let lending_protocol = borrow_global_mut<LendingProtocol>(@p2p_lending);
        
        // Get next loan ID
        let loan_id = lending_protocol.next_loan_id;
        lending_protocol.next_loan_id = loan_id + 1;
        
        // Create loan info
        let now = timestamp::now_seconds();
        let loan_info = LoanInfo {
            loan_id,
            borrower: borrower_addr,
            lender: @0x0, // Will be set when funded
            loan_amount,
            interest_rate,
            term_in_seconds,
            created_at: now,
            status: LOAN_STATUS_PENDING,
        };
        
        // Store loan info
        table::add(&mut lending_protocol.loans, loan_id, loan_info);
    }

    /// Fund a loan request
    public entry fun fund_loan<CoinType>(
        lender: &signer,
        loan_id: u64
    ) acquires LendingProtocol {
        let lender_addr = signer::address_of(lender);
        
        // Get lending protocol
        let lending_protocol = borrow_global_mut<LendingProtocol>(@p2p_lending);
        
        // Ensure loan exists
        assert!(table::contains(&lending_protocol.loans, loan_id), error::not_found(E_LOAN_NOT_FOUND));
        
        // Get loan info
        let loan_info = table::borrow_mut(&mut lending_protocol.loans, loan_id);
        
        // Ensure loan is pending
        assert!(loan_info.status == LOAN_STATUS_PENDING, error::invalid_state(E_LOAN_ALREADY_FUNDED));
        
        // Transfer loan amount from lender to borrower
        let loan_coins = coin::withdraw<CoinType>(lender, loan_info.loan_amount);
        coin::deposit(loan_info.borrower, loan_coins);
        
        // Update loan information
        loan_info.status = LOAN_STATUS_ACTIVE;
        loan_info.lender = lender_addr;
    }
}