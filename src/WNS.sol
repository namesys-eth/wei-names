// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Auth} from "./registry/Auth.sol";
import {Registry} from "./registry/Registry.sol";
import {Resolver} from "./resolver/Resolver.sol";
import {Bridge} from "./registry/Bridge.sol";

contract WNS is Registry, Resolver, Bridge {
    constructor(address o) {
        _initOwner(o);
    }
}
