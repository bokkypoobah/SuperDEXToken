pragma solidity ^0.4.11;

// ----------------------------------------------------------------------------
// OAX 'openANX Token' crowdfunding contract
//
// Refer to http://openanx.org/ for further information.
//
// Enjoy. (c) openANX and BokkyPooBah / Bok Consulting Pty Ltd 2017. 
// The MIT Licence.
// ----------------------------------------------------------------------------

import "./ERC20Interface.sol";
import "./Owned.sol";
import "./SafeMath.sol";
import "./LockedTokens.sol";
import "./OpenANXTokenConfig.sol";


// ----------------------------------------------------------------------------
// ERC20 Token, with the addition of symbol, name and decimals
// ----------------------------------------------------------------------------
contract ERC20Token is ERC20Interface, Owned {
    using SafeMath for uint;

    // ------------------------------------------------------------------------
    // symbol(), name() and decimals()
    // ------------------------------------------------------------------------
    string public symbol;
    string public name;
    uint8 public decimals;

    // ------------------------------------------------------------------------
    // Balances for each account
    // ------------------------------------------------------------------------
    mapping(address => uint) balances;

    // ------------------------------------------------------------------------
    // Owner of account approves the transfer of an amount to another account
    // ------------------------------------------------------------------------
    mapping(address => mapping (address => uint)) allowed;


    // ------------------------------------------------------------------------
    // Constructor
    // ------------------------------------------------------------------------
    function ERC20Token(
        string _symbol, 
        string _name, 
        uint8 _decimals, 
        uint _totalSupply
    ) Owned() {
        symbol = _symbol;
        name = _name;
        decimals = _decimals;
        totalSupply = _totalSupply;
        balances[owner] = _totalSupply;
    }


    // ------------------------------------------------------------------------
    // Get the account balance of another account with address _owner
    // ------------------------------------------------------------------------
    function balanceOf(address _owner) constant returns (uint balance) {
        return balances[_owner];
    }


    // ------------------------------------------------------------------------
    // Transfer the balance from owner's account to another account
    // ------------------------------------------------------------------------
    function transfer(address _to, uint _amount) returns (bool success) {
        if (balances[msg.sender] >= _amount             // User has balance
            && _amount > 0                              // Non-zero transfer
            && balances[_to] + _amount > balances[_to]  // Overflow check
        ) {
            balances[msg.sender] = balances[msg.sender].sub(_amount);
            balances[_to] = balances[_to].add(_amount);
            Transfer(msg.sender, _to, _amount);
            return true;
        } else {
            return false;
        }
    }


    // ------------------------------------------------------------------------
    // Allow _spender to withdraw from your account, multiple times, up to the
    // _value amount. If this function is called again it overwrites the
    // current allowance with _value.
    // ------------------------------------------------------------------------
    function approve(
        address _spender,
        uint _amount
    ) returns (bool success) {
        allowed[msg.sender][_spender] = _amount;
        Approval(msg.sender, _spender, _amount);
        return true;
    }


    // ------------------------------------------------------------------------
    // Spender of tokens transfer an amount of tokens from the token owner's
    // balance to another account. The owner of the tokens must already
    // have approve(...)-d this transfer
    // ------------------------------------------------------------------------
    function transferFrom(
        address _from,
        address _to,
        uint _amount
    ) returns (bool success) {
        if (balances[_from] >= _amount                  // From a/c has balance
            && allowed[_from][msg.sender] >= _amount    // Transfer approved
            && _amount > 0                              // Non-zero transfer
            && balances[_to] + _amount > balances[_to]  // Overflow check
        ) {
            balances[_from] = balances[_from].sub(_amount);
            allowed[_from][msg.sender] = allowed[_from][msg.sender].sub(_amount);
            balances[_to] = balances[_to].add(_amount);
            Transfer(_from, _to, _amount);
            return true;
        } else {
            return false;
        }
    }


    // ------------------------------------------------------------------------
    // Returns the amount of tokens approved by the owner that can be
    // transferred to the spender's account
    // ------------------------------------------------------------------------
    function allowance(
        address _owner, 
        address _spender
    ) constant returns (uint remaining) {
        return allowed[_owner][_spender];
    }
}


// ----------------------------------------------------------------------------
// openANX crowdsale token smart contract
// ----------------------------------------------------------------------------
contract OpenANXToken is ERC20Token, OpenANXTokenConfig {

    // ------------------------------------------------------------------------
    // Has the crowdsale been finalised?
    // ------------------------------------------------------------------------
    bool public finalised = false;

    // ------------------------------------------------------------------------
    // Number of tokens per 1,000 ETH
    // This can be adjusted as the ETH/USD rate changes
    //
    // Indicative rate of ETH per token of 0.00290923 at 8 June 2017
    // 
    // This is the same as 1 / 0.00290923 = 343.733565238912015 OAX per ETH
    //
    // tokensPerEther  = 343.733565238912015
    // tokensPerKEther = 343,733.565238912015
    // tokensPerKEther = 343,734 rounded to an uint, six significant figures
    // ------------------------------------------------------------------------
    uint public tokensPerKEther = 343734;

    // ------------------------------------------------------------------------
    // Locked Tokens - holds the 1y and 2y locked tokens information
    // ------------------------------------------------------------------------
    LockedTokens public lockedTokens;

    // ------------------------------------------------------------------------
    // Wallet receiving the raised funds 
    // ------------------------------------------------------------------------
    address public wallet;

    // ------------------------------------------------------------------------
    // Crowdsale participant's accounts need to be KYC verified KYC before
    // the participant can move their tokens
    // ------------------------------------------------------------------------
    mapping(address => bool) public kycRequired;


    // ------------------------------------------------------------------------
    // Constructor
    // ------------------------------------------------------------------------
    function OpenANXToken(address _wallet) 
        ERC20Token(SYMBOL, NAME, DECIMALS, 0)
    {
        wallet = _wallet;
        lockedTokens = new LockedTokens(this);
    }

    // ------------------------------------------------------------------------
    // openANX can change the crowdsale wallet address
    // Can be set at any time before or during the crowdsale
    // Not relevant after the crowdsale is finalised as no more contributions
    // are accepted
    // ------------------------------------------------------------------------
    function setWallet(address _wallet) onlyOwner {
        wallet = _wallet;
        WalletUpdated(wallet);
    }
    event WalletUpdated(address newWallet);


    // ------------------------------------------------------------------------
    // openANX can set number of tokens per 1,000 ETH
    // Can only be set before the start of the crowdsale
    // ------------------------------------------------------------------------
    function setTokensPerKEther(uint _tokensPerKEther) onlyOwner {
        if (now >= START_DATE) throw;
        if (_tokensPerKEther == 0) throw;
        tokensPerKEther = _tokensPerKEther;
        TokensPerKEtherUpdated(tokensPerKEther);
    }
    event TokensPerKEtherUpdated(uint tokensPerKEther);


    // ------------------------------------------------------------------------
    // Accept ethers to buy tokens during the crowdsale
    // ------------------------------------------------------------------------
    function () payable {
        // No contributions after the crowdsale is finalised
        if (finalised) throw;

        // No contributions before the start of the crowdsale
        if (now < START_DATE) throw;
        // No contributions after the end of the crowdsale
        if (now > END_DATE) throw;

        // No contributions below the minimum (can be 0 ETH)
        if (msg.value == 0 || msg.value < CONTRIBUTIONS_MIN) throw;
        // No contributions above a maximum (if maximum is set to non-0)
        if (CONTRIBUTIONS_MAX > 0 && msg.value > CONTRIBUTIONS_MAX) throw;

        // Calculate number of tokens for contributed ETH
        // `18` is the ETH decimals
        // `- decimals` is the token decimals
        // `+ 3` for the tokens per 1,000 ETH factor
        uint tokens = msg.value * tokensPerKEther / 10**uint(18 - decimals + 3);

        // Check if the hard cap will be exceeded
        if (totalSupply + tokens > TOKENS_HARD_CAP) throw;

        // Add tokens purchased to account's balance and total supply
        balances[msg.sender] = balances[msg.sender].add(tokens);
        totalSupply = totalSupply.add(tokens);

        // Log the tokens purchased 
        Transfer(0x0, msg.sender, tokens);
        TokensBought(msg.sender, msg.value, this.balance, tokens,
             totalSupply, tokensPerKEther);

        // KYC verification required before participant can transfer the tokens
        kycRequired[msg.sender] = true;

        // Transfer the contributed ethers to the crowdsale wallet
        if (!wallet.send(msg.value)) throw;
    }
    event TokensBought(address indexed buyer, uint ethers, 
        uint newEtherBalance, uint tokens, uint newTotalSupply, 
        uint tokensPerKEther);


    // ------------------------------------------------------------------------
    // openANX to finalise the crowdsale - to adding the locked tokens to 
    // this contract and the total supply
    // ------------------------------------------------------------------------
    function finalise() onlyOwner {
        // Can only finalise if raised > soft cap or after the end date
        if (totalSupply < TOKENS_SOFT_CAP && now < END_DATE) throw;

        // Can only finalise once
        if (finalised) throw;

        // Calculate and add remaining tokens to locked balances
        lockedTokens.addRemainingTokens();

        // Allocate locked and premined tokens
        balances[this] = balances[this].add(lockedTokens.totalSupplyLocked());
        totalSupply = totalSupply.add(lockedTokens.totalSupplyLocked());

        // Can only finalise once
        finalised = true;
    }


    // ------------------------------------------------------------------------
    // openANX to add precommitment funding token balance before the crowdsale
    // commences
    // ------------------------------------------------------------------------
    function addPrecommitment(address participant, uint balance) onlyOwner {
        if (now >= START_DATE) throw;
        if (balance == 0) throw;
        balances[participant] = balances[participant].add(balance);
        totalSupply = totalSupply.add(balance);
        Transfer(0x0, participant, balance);
    }
    event PrecommitmentAdded(address indexed participant, uint balance);


    // ------------------------------------------------------------------------
    // Transfer the balance from owner's account to another account, with KYC
    // verification check for the crowdsale participant's first transfer
    // ------------------------------------------------------------------------
    function transfer(address _to, uint _amount) returns (bool success) {
        // Cannot transfer before crowdsale ends
        if (!finalised) throw;
        // Cannot transfer if KYC verification is required
        if (kycRequired[msg.sender]) throw;
        // Standard transfer
        return super.transfer(_to, _amount);
    }


    // ------------------------------------------------------------------------
    // Spender of tokens transfer an amount of tokens from the token owner's
    // balance to another account, with KYC verification check for the
    // crowdsale participant's first transfer
    // ------------------------------------------------------------------------
    function transferFrom(address _from, address _to, uint _amount) 
        returns (bool success)
    {
        // Cannot transfer before crowdsale ends
        if (!finalised) throw;
        // Cannot transfer if KYC verification is required
        if (kycRequired[_from]) throw;
        // Standard transferFrom
        return super.transferFrom(_from, _to, _amount);
    }


    // ------------------------------------------------------------------------
    // openANX to KYC verify the participant's account
    // ------------------------------------------------------------------------
    function kycVerify(address participant) onlyOwner {
        kycRequired[participant] = false;
        KycVerified(participant);
    }
    event KycVerified(address indexed participant);


    // ------------------------------------------------------------------------
    // openANX can transfer out any accidentally sent ERC20 tokens
    // ------------------------------------------------------------------------
    function transferAnyERC20Token(address tokenAddress, uint amount)
      onlyOwner returns (bool success) 
    {
        return ERC20Interface(tokenAddress).transfer(owner, amount);
    }
}