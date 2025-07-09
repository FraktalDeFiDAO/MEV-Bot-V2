pragma solidity ^0.8.0;

import "../src/interfaces/IDiamond.sol";
import "../src/interfaces/IDiamondLoupe.sol";
import "../lib/forge-std/src/Test.sol";
import "../lib/solidity-stringutils/strings.sol";

abstract contract HelperContract is IDiamond, IDiamondLoupe, Test {
    using strings for *;

    function generateSelectors(string memory _facetName) internal pure returns (bytes4[] memory selectors) {
        bytes32 facetNameHash = keccak256(bytes(_facetName));

        if (facetNameHash == keccak256(bytes("DiamondCutFacet"))) {
            selectors = new bytes4[](1);
            selectors[0] = 0x1f931c1c; // diamondCut((address,uint8,bytes4[])[],address,bytes)
            return selectors;
        }
        if (facetNameHash == keccak256(bytes("DiamondLoupeFacet"))) {
            selectors = new bytes4[](5);
            selectors[0] = 0xcdffacc6; // facetAddress(bytes4)
            selectors[1] = 0x52ef6b2c; // facetAddresses()
            selectors[2] = 0xadfca15e; // facetFunctionSelectors(address)
            selectors[3] = 0x7a0ed627; // facets()
            selectors[4] = 0x01ffc9a7; // supportsInterface(bytes4)
            return selectors;
        }
        // FIX: Removed the entry for the redundant OwnershipFacet.
        if (facetNameHash == keccak256(bytes("AccessControlFacet"))) {
            selectors = new bytes4[](11);
            selectors[0] = 0x79ba5097; // acceptOwnership()
            selectors[1] = 0x248a9ca3; // getRoleAdmin(bytes32)
            selectors[2] = 0x2f2ff15d; // grantRole(bytes32,address)
            selectors[3] = 0x91d14854; // hasRole(bytes32,address)
            selectors[4] = 0x1975fd91; // initializeRoles(address,bytes32,bytes32,bytes32)
            selectors[5] = 0x8da5cb5b; // owner()
            selectors[6] = 0xe30c3978; // pendingOwner()
            selectors[7] = 0x36568abe; // renounceRole(bytes32,address)
            selectors[8] = 0xd547741f; // revokeRole(bytes32,address)
            selectors[9] = 0x1e4e0091; // setRoleAdmin(bytes32,bytes32)
            selectors[10] = 0xf2fde38b; // transferOwnership(address)
            return selectors;
        }
        if (facetNameHash == keccak256(bytes("ContractRegistryFacet"))) {
            selectors = new bytes4[](13);
            selectors[0] = 0x82416232; // addContract(string,address,uint16)
            selectors[1] = 0x1c6dbe2f; // addContractType(string)
            selectors[2] = 0xa3d4551b; // getContractByAddress(address)
            selectors[3] = 0x8aa3e011; // getContractInfo(uint256)
            selectors[4] = 0xc310e750; // getContractType(uint16)
            selectors[5] = 0xbb50c142; // getNextContractId()
            selectors[6] = 0x027e854b; // getNextContractTypeId()
            selectors[7] = 0x1a9a6c95; // hasContract(address)
            selectors[8] = 0x1cdeae1a; // hasContractType(string)
            selectors[9] = 0x3ac2b140; // initializeContractRegistry(address)
            selectors[10] = 0x64e9d732; // isContractActive(address)
            selectors[11] = 0x25d31360; // setContractActive(address,bool)
            selectors[12] = 0x7669f9e1; // setNextContractId(uint256)
            return selectors;
        }
        if (facetNameHash == keccak256(bytes("TokenHelperFacet"))) {
            selectors = new bytes4[](9);
            selectors[0] = 0x0d1ce2d2; // activateToken(address)
            selectors[1] = 0xd48bfca7; // addToken(address)
            selectors[2] = 0x68173bcf; // deactivateToken(address)
            selectors[3] = 0x70fb4d5c; // fetchTokenInfo(address)
            selectors[4] = 0x0b4c695b; // getTokenById(uint16)
            selectors[5] = 0x8cba7be4; // getTokenIdByAddress(address)
            selectors[6] = 0x9bb0f599; // hasToken(address)
            selectors[7] = 0xa4785bad; // initializeTokenHelper(address)
            selectors[8] = 0xe2f1b792; // setTokenActive(address,bool)
            return selectors;
        }
        if (facetNameHash == keccak256(bytes("ExchangeHelperFacet"))) {
            selectors = new bytes4[](13);
            selectors[0] = 0xa1467cf9; // addExchange(string,uint256,uint8,uint8,bool,address)
            selectors[1] = 0x591f6326; // addExchangeContract(address,string,uint16)
            selectors[2] = 0x355a5116; // detectExchangeType(address)
            selectors[3] = 0xdc6927e8; // getExchangeById(uint16)
            selectors[4] = 0x07e89db4; // getExchangeByIdAndFactory(uint16,uint256)
            selectors[5] = 0x6c159707; // getExchangeHelperStorageOwner()
            selectors[6] = 0x59bde97a; // getPoolOrPairAddress((uint256,uint256,uint256,uint24,bytes32))
            selectors[7] = 0x7b68c0ac; // hasExchange(string)
            selectors[8] = 0xd3f06174; // initializeExchangeHelper(address,address,address)
            selectors[9] = 0xb0460788; // isExchangeType(address,uint8)
            selectors[10] = 0x677ebc4f; // setExchangeActive(uint16,bool)
            selectors[11] = 0x9023d948; // setExchangeContractActive(address,bool)
            selectors[12] = 0xd6ffd067; // transferExchangeHelperStorageOwnership(address)
            return selectors;
        }
        if (facetNameHash == keccak256(bytes("ArbitrageFacet"))) {
            selectors = new bytes4[](4);
            selectors[0] = 0xa4a2f824; // executeAaveArbitrage(address,uint256,(address,address,address,address,uint16,uint16,uint16,uint256,uint256,address,bytes),(address,address,address,address,uint16,uint16,uint16,uint256,uint256,address,bytes),uint256)
            selectors[1] = 0x920f5c84; // executeOperation(address[],uint256[],uint256[],address,bytes)
            selectors[2] = 0xc0c53b8b; // initialize(address,address,address)
            selectors[3] = 0x5e35359e; // withdrawTokens(address,address,uint256)
            return selectors;
        }
        if (facetNameHash == keccak256(bytes("Test1Facet"))) {
            selectors = new bytes4[](21);
            selectors[0] = 0x8126e423; // test1Func1()
            selectors[1] = 0x19e3b533; // test1Func2()
            selectors[2] = 0x0716c2ae; // test1Func3()
            selectors[3] = 0x11046047; // test1Func4()
            selectors[4] = 0xcf3bbe18; // test1Func5()
            selectors[5] = 0x24c1d5a7; // test1Func6()
            selectors[6] = 0xcbb835f6; // test1Func7()
            selectors[7] = 0x0165a18b; // test1Func8()
            selectors[8] = 0x697d8193; // test1Func9()
            selectors[9] = 0x88340479; // test1Func10()
            selectors[10] = 0x29713551; // test1Func11()
            selectors[11] = 0xcd4a6f98; // test1Func12()
            selectors[12] = 0xde234f43; // test1Func13()
            selectors[13] = 0x905739a3; // test1Func14()
            selectors[14] = 0x15391c21; // test1Func15()
            selectors[15] = 0x02162529; // test1Func16()
            selectors[16] = 0x0874175E; // test1Func17()
            selectors[17] = 0x6354a737; // test1Func18()
            selectors[18] = 0x74267352; // test1Func19()
            selectors[19] = 0x11ae8342; // test1Func20()
            selectors[20] = 0x01ffc9a7; // supportsInterface(bytes4)
            return selectors;
        }
        if (facetNameHash == keccak256(bytes("Test2Facet"))) {
            selectors = new bytes4[](20);
            selectors[0] = 0xef2c2329; // test2Func1()
            selectors[1] = 0x00f3548b; // test2Func2()
            selectors[2] = 0x916e9595; // test2Func3()
            selectors[3] = 0x38839a33; // test2Func4()
            selectors[4] = 0x7c5b3666; // test2Func5()
            selectors[5] = 0x58370333; // test2Func6()
            selectors[6] = 0x438a9355; // test2Func7()
            selectors[7] = 0x53a99282; // test2Func8()
            selectors[8] = 0x905739a3; // test2Func9()
            selectors[9] = 0x15391c21; // test2Func10()
            selectors[10] = 0x02162529; // test2Func11()
            selectors[11] = 0x0874175e; // test2Func12()
            selectors[12] = 0x6354a737; // test2Func13()
            selectors[13] = 0x74267352; // test2Func14()
            selectors[14] = 0x11ae8342; // test2Func15()
            selectors[15] = 0x234a23de; // test2Func16()
            selectors[16] = 0x29713551; // test2Func17()
            selectors[17] = 0xcd4a6f98; // test2Func18()
            selectors[18] = 0xde234f43; // test2Func19()
            selectors[19] = 0x8126e423; // test2Func20()
            return selectors;
        }
        return new bytes4[](0);
    }
    
    function removeElement(uint256 index, bytes4[] memory array) public pure returns (bytes4[] memory) {
        if (index >= array.length) return array;
        bytes4[] memory newarray = new bytes4[](array.length - 1);
        uint256 j = 0;
        for (uint256 i = 0; i < array.length; i++) {
            if (i != index) {
                newarray[j] = array[i];
                j++;
            }
        }
        return newarray;
    }

    function removeElement(bytes4 el, bytes4[] memory array) public pure returns (bytes4[] memory) {
        for (uint256 i = 0; i < array.length; i++) {
            if (array[i] == el) {
                return removeElement(i, array);
            }
        }
        return array;
    }

    function containsElement(bytes4[] memory array, bytes4 el) public pure returns (bool) {
        for (uint256 i = 0; i < array.length; i++) {
            if (array[i] == el) {
                return true;
            }
        }
        return false;
    }

    function containsElement(address[] memory array, address el) public pure returns (bool) {
        for (uint256 i = 0; i < array.length; i++) {
            if (array[i] == el) {
                return true;
            }
        }
        return false;
    }

    function sameMembers(bytes4[] memory array1, bytes4[] memory array2) public pure returns (bool) {
        if (array1.length != array2.length) {
            return false;
        }
        for (uint256 i = 0; i < array1.length; i++) {
            if (!containsElement(array2, array1[i])) {
                return false;
            }
        }
        return true;
    }

    function getAllSelectors(address diamondAddress) public view returns (bytes4[] memory) {
        Facet[] memory facetList = IDiamondLoupe(diamondAddress).facets();
        uint256 len = 0;
        for (uint256 i = 0; i < facetList.length; i++) {
            len += facetList[i].functionSelectors.length;
        }

        uint256 pos = 0;
        bytes4[] memory selectors = new bytes4[](len);
        for (uint256 i = 0; i < facetList.length; i++) {
            for (uint256 j = 0; j < facetList[i].functionSelectors.length; j++) {
                selectors[pos] = facetList[i].functionSelectors[j];
                pos++;
            }
        }
        return selectors;
    }

    // Dummy implementations required by the interfaces for this abstract contract to compile.
    function diamondCut(FacetCut[] calldata _diamondCut, address _init, bytes calldata _calldata) external virtual {}
    function facetAddress(bytes4 _functionSelector) external view virtual returns (address facetAddress_) {}
    function facetAddresses() external view virtual returns (address[] memory facetAddresses_) {}
    function facetFunctionSelectors(address _facet) external view virtual returns (bytes4[] memory facetFunctionSelectors_) {}
    function facets() external view virtual returns (Facet[] memory facets_) {}
}
