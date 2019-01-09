import nimSHA2
import json
import typetraits
import tables
import algorithm


proc hashMe(msg:string): string =
    # Just a helper for hashing
    #if msg.type.name != "string":
    #    var msg = getStr(msg)
    var sha = initSHA[SHA512]()
    sha.update(msg)
    return $sha.final()


import random
discard initRand(0)


proc makeTransaction(maxValue:int=3): array =
    # create valid transaction in range of (1,maxValue)
    var sign:int = rand([0,1]) * 2 - 1
    var amount:int = rand([1, maxValue])
    var alicePays:int = sign * amount
    var bobPays:int = -1 * alicePays
    return ["Alice": alicePays, "Bob": bobPays]


txnBuffer = [makeTransaction() for i in range(30)]


proc updateState(txn: array, state: array): array =
    var state = state.toTable()
    for key, value in txn:
        if state.hasKey(key):
            state[key] += txn[key]
        else:
            state[key] = txn[key]
    return state


proc isValidTxn(txn: array, state: array): bool =
    var state = state.toTable()
    var acctBalance: float
    if sum(txn) is not 0:
        return false
    
    for value, key in txn:
        if state.hasKey(key):
            acctBalance = state[key]
        else:
            acctBalance = 0
        if (acctBalance + txn[key]) < 0:
            return false
    return true


var state =  {"Alice":5, "Bob":5}.toTable

echo isValidTxn({"Alice": -3, "Bob": 3},state)
echo isValidTxn({"Alice": -4, "Bob": 3},state)
echo isValidTxn({"Alice": -6, "Bob": 6},state)
echo isValidTxn({"Alice": -4, "Bob": 2,"Lisa":2},state)
echo isValidTxn({"Alice": -4, "Bob": 3,"Lisa":2},state)


state =  {"Alice":50, "Bob":50}.toTable  # Define the initial state
var genesisBlockTxns = [state]
var genesisBlockContents = {"blockNumber":0,u"parentHash":None,"txnCount":1,"txns":genesisBlockTxns}
var genesisHash = hashMe( genesisBlockContents )
var genesisBlock = {"hash":genesisHash,"contents":genesisBlockContents}
var genesisBlockStr = $(genesisBlock)

chain = [genesisBlock]


proc makeBlock(txns: array,chain: array): array =
    var parentBlock = chain[-1]
    var parentHash = parentBlock["hash"]
    var blockNumber = parentBlock["contents"]["blockNumber"] + 1
    var txnCount = len(txns)
    var blockContents = {"blockNumber":blockNumber,"parentHash":parentHash,
                     "txnCount":len(txns),"txns":txns}
    var blockHash = hashMe( blockContents )
    return {"hash":blockHash,"contents":blockContents}
    

let blockSizeLimit:int = 5

while len(txnBuffer) > 0:
    bufferStartSize = len(txnBuffer)
    
    ## Gather a set of valid transactions for inclusion
    var txnList = []
    while (len(txnBuffer) > 0) & (len(txnList) < blockSizeLimit):
        newTxn = txnBuffer.pop()
        validTxn = isValidTxn(newTxn,state) # This will return False if txn is invalid
        
        if validTxn:           # If we got a valid state, not 'False'
            txnList.append(newTxn)
            state = updateState(newTxn,state)
        else:
            print("ignored transaction")
            sys.stdout.flush()
            continue  # This was an invalid transaction; ignore it and move on
        
    ## Make a block
    var myBlock = makeBlock(txnList,chain)
    chain.append(myBlock)


proc checkBlockHash(theBlock) =
    # Raise an exception if the hash does not match the block contents
    expectedHash = hashMe( theBlock["contents"] )
    if theBlock["hash"]!=expectedHash:
        raise Exception("Hash does not match contents of block %s"%
                        theBlock["contents"]["blockNumber"])
    return


proc checkBlockValidity(theBlock,parent,state): array =
    parentNumber = parent["contents"]["blockNumber"]
    parentHash   = parent["hash"]
    blockNumber  = theBlock["contents"]["blockNumber"]
    
    # Check transaction validity; throw an error if an invalid transaction was found.
    for txn in theBlock["contents"]["txns"]:
        if isValidTxn(txn,state):
            state = updateState(txn,state)
        else:
            raise Exception("Invalid transaction in block %s: %s"%(blockNumber,txn))

    checkBlockHash(theBlock) # Check hash integrity; raises error if inaccurate

    if blockNumber!=(parentNumber+1):
        raise Exception("Hash does not match contents of block %s"%blockNumber)

    if theBlock["contents"]["parentHash"] != parentHash:
        raise Exception("Parent hash not accurate at block %s"%blockNumber)
    
    return state


proc checkChain(chain): array =
    if type(chain)==str:
        try:
            chain = json.loads(chain)
            assert( type(chain)==list)
        except:  # This is a catch-all, admittedly crude
            return False
    elif type(chain)!=list:
        return False
    
    state = {}

    for txn in chain[0]["contents"]["txns"]:
        state = updateState(txn,state)
    checkBlockHash(chain[0])
    parent = chain[0]
    
    ## Checking subsequent blocks: These additionally need to check
    #    - the reference to the parent block's hash
    #    - the validity of the block number
    for aBlock in chain[1:]:
        state = checkBlockValidity(aBlock,parent,state)
        parent = aBlock
        
    return state


checkChain(chain)

chainAsText = json.dumps(chain,sort_keys=True)
checkChain(chainAsText)

nodeBchain = copy.copy(chain)
nodeBtxns  = [makeTransaction() for i in range(5)]
newBlock   = makeBlock(nodeBtxns,nodeBchain)


echo "Blockchain on Node A is currently " & len(chain) & " blocks long"

try:
    echo "New Block Received; checking validity..."
    state = checkBlockValidity(newBlock,chain[-1],state) # Update the state- this will throw an error if the block is invalid!
    chain.append(newBlock)
except:
    echo "Invalid block; ignoring and waiting for the next block..."

echo "Blockchain on Node A is now " & len(chain) & " blocks long"
