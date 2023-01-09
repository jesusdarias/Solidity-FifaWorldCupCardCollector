// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.7;

contract FifaWorldCupCardCollector {

    uint public constant PACK_PRICE = 100;
    uint public constant CARDS_PER_PACK = 5;
    uint public constant N_COLLECTIBLES=33;
    uint public constant MAX_LISTINGS=5;

    struct Listing {
        bool active;
        address payable account;
        int8 id_give;
        uint256 eth_give;
        int8 id_receive;
        uint256 eth_receive;
    }

    struct Account {
        uint256[] listings; //max 5 listings per account. Stores indexes of listings in the market.
        uint256[N_COLLECTIBLES] cards;  //one collectible card per WC team plus the world cup. The index represents the card id. The value represents the quantity of that particular card. 
    }

    Listing[] public market;
    mapping (address => Account) private accounts;
    uint256 private num_existent_cards;
    address payable private owner;
    uint256 private deposit;

    event PackOpened(address account);
    event NewListing(uint256 listing_id, address lister, int8 id_give, uint256 eth_give, int8 id_receive, uint256 eth_receive);
    event ListingAccepted(uint256 listing_id, address lister, address buyer, int8 id_give, uint256 eth_give, int8 id_receive, uint256 eth_receive);
    event ListingCanceled(uint256 listing_id, address lister, int8 id_give, uint256 eth_give, int8 id_receive, uint256 eth_receive);

    constructor() {
        owner = payable(msg.sender);
    }

    function openPack() external payable{

        require( msg.value==PACK_PRICE , "The exact amount of money specified to buy a pack must be sent.");
        deposit+=msg.value;

        for(uint i = 0; i<CARDS_PER_PACK;i++)
        {
            num_existent_cards++;
            accounts[msg.sender].cards[(uint256(keccak256(abi.encodePacked(num_existent_cards)))) % N_COLLECTIBLES]++;
        }

        emit PackOpened(msg.sender);
    }

    /**
        The player creating the Listing can choose to send money to the buyers as part of the operation
        The contract stores the money sent by the lister, which is then transferred to the buyer when the listing is accepted.
    */
    function makeListing(int8 id_give, uint256 eth_give, int8 id_receive) external payable {  

        //lister must not have more than MAX_LISTINGS active listings
        require(accounts[msg.sender].listings.length<MAX_LISTINGS, "You have reached the maximum number of active listings. Consider canceling one before creating a new listing.");

        //checking id of cards is valid. id=-1 means no card is offered/expected.
        require(id_give==-1 || id_give>=0 && id_give<int(N_COLLECTIBLES), "The specified id of the card to be given is invalid.");
        require(id_receive==-1 || (id_receive>=0 && id_receive<int(N_COLLECTIBLES)), "The specified id of the card to be received is invalid.");


        //lister must have more than one of the card type being offered in his inventory, from where it is removed (unless the listing is canceled)
        if(id_receive!=-1)
        {
            require(accounts[msg.sender].cards[uint256(int256(id_receive))]>1, "The card cannot be offered as there is no duplicates in your inventory.");
            accounts[msg.sender].cards[uint256(int256(id_receive))]--;
        }

        //create listing
        emit NewListing(market.length, msg.sender, id_give, eth_give, id_receive, msg.value);
        accounts[msg.sender].listings.push(market.length);  
        market.push(Listing({
                        active: true,
                        account: payable(msg.sender),
                        id_give: id_give,
                        eth_give: eth_give, //if any money was sent to this function, it will be sent to the buyer when the listing is accepted.
                        id_receive: id_receive,
                        eth_receive: msg.value
                    }));
    }

    function deleteListingFromAccount(uint256 listing_id) private {
        
        //To avoid gaps in the market array, we move the last listing to the position of the listing to be deleted, and then delete the last item.
        //It is also necessary to update the pointers of the personal accounts involved.
        address lister = address(market[listing_id].account);
        bool found=false;
        uint i = 0;
        while(!found)
        {
            found=(accounts[lister].listings[i]==listing_id);
            if(found)
            {
                //To avoid gaps in the listing array, we move the last listing to the position of the listing to be deleted, and then delete the last item.
                accounts[lister].listings[i]=accounts[lister].listings[accounts[lister].listings.length-1]; //the pointer of the last listing of the lister's account is also swapped with the deleted one.
                accounts[lister].listings.pop(); 
            }
            i++;
        }
    }


    function acceptListing(uint256 listing_id) external payable{
        
        require(listing_id>=0 && listing_id<market.length, "The specified listing does not exist.");
        require(market[listing_id].active, "The specified listing is no longer active.");
        require(msg.value==market[listing_id].eth_give,"The exact amount of money specified by the listing must be sent.");

        //buyer must have more than one of the card to give to the lister (unless no card is required for the transaction)  
        if(market[listing_id].id_give!=-1)
        {
            require(accounts[msg.sender].cards[uint256(int256(market[listing_id].id_give))]>1, "You must have more than one card in your inventory before trading it.");
            accounts[msg.sender].cards[uint256(int256(market[listing_id].id_give))]--;                           //remove card from buyer
            accounts[address(market[listing_id].account)].cards[uint256(int256(market[listing_id].id_give))]++;  //transfer card to lister
        } 

        if(market[listing_id].id_receive!=-1)
        {
            accounts[msg.sender].cards[uint256(int256(market[listing_id].id_receive))]++;                      //send card to buyer (card was previously on hold when the listing was created)
        } 

        payable(msg.sender).transfer(market[listing_id].eth_receive);
        market[listing_id].account.transfer(msg.value);
 
        emit ListingAccepted(listing_id,address(market[listing_id].account), msg.sender, market[listing_id].id_give, msg.value, market[listing_id].id_receive, market[listing_id].eth_receive);
        deleteListingFromAccount(listing_id);
        delete market[listing_id];
        
    }

    function cancelListing(uint256 listing_id) external {

        require(listing_id<=market.length, "The specified listing does not exist.");
        require(msg.sender==address(market[listing_id].account), "Only the person who created the listing can cancel it.");

        //The card offered by the lister and the ethereum provided is returned
        if(market[listing_id].id_receive!=-1)
            accounts[msg.sender].cards[uint256(int256(market[listing_id].id_receive))]++;
        if(market[listing_id].eth_receive>0)
            market[listing_id].account.transfer(market[listing_id].eth_receive);

        emit ListingCanceled(listing_id, msg.sender, market[listing_id].id_give, market[listing_id].eth_give, market[listing_id].id_receive, market[listing_id].eth_receive);
        deleteListingFromAccount(listing_id);
        delete market[listing_id];
    }

    function withdrawal() public {
        require( msg.sender == owner ,"Only the owner of the contract can withdraw from the deposit.");
        owner.transfer(deposit);
        deposit=0;
    }

    function checkDeposit() public view returns (uint256){
        require( msg.sender == owner ,"Only the owner of the contract can check the deposit.");
        return deposit;
    }

    function myListings() public view returns (uint256[] memory){
        return accounts[msg.sender].listings;
    }

    function myCollection() public view returns (uint256[N_COLLECTIBLES] memory){
        return accounts[msg.sender].cards;
    }

    function checkAccountListings(address account) public view returns (uint256[] memory){
        return accounts[account].listings;
    }

    function checkAccountCollection(address account) public view returns (uint256[N_COLLECTIBLES] memory){
        return accounts[account].cards;
    }

}
