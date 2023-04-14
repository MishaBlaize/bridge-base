import type { SnapshotRestorer } from "@nomicfoundation/hardhat-network-helpers";
import { takeSnapshot } from "@nomicfoundation/hardhat-network-helpers";
import {BigNumber} from "ethers";
import { expect } from "chai";
import { ethers, upgrades } from "hardhat";
import type { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

import {
    UniswapV2Factory,
    UniswapV2Pair,
    BridgeWithSwap,
    MockToken,
    MockNative,
    UniswapV2Router02 } from "../typechain-types";

describe("BridgeWithSwap", function () {
    let snapshotA: SnapshotRestorer;

    // Signers.
    let deployer: SignerWithAddress,
        user: SignerWithAddress,
        user2: SignerWithAddress,
        relayer: SignerWithAddress,
        feeTo: SignerWithAddress,
        tokenOnSecondChain: SignerWithAddress;
    let pairUniV2: UniswapV2Pair;
    let factoryUniV2: UniswapV2Factory;
    let routerUniV2: UniswapV2Router02;

    let bridge: BridgeWithSwap;
    let mockERC20: MockToken;
    let mockNative: MockNative;

    const FIVE_MINUTES = 300;
    before(async () => {
        // Getting of signers.
        [deployer, user, user2, relayer, tokenOnSecondChain, feeTo] = await ethers.getSigners();

        // Deployment of the mocks.
        const MockERC20 = await ethers.getContractFactory("MockToken", deployer);
        mockERC20 = await MockERC20.deploy("MockERC20", "ERC20", 18);
        await mockERC20.deployed();

        const MockNative = await ethers.getContractFactory("MockNative", deployer);
        mockNative = await MockNative.deploy("MockNative", "NATIVE");
        // Deploy UniSwapV2
        const UniV2Factory = await ethers.getContractFactory("UniswapV2Factory");
        factoryUniV2 = await UniV2Factory.connect(deployer).deploy(deployer.address);
        await factoryUniV2.deployed();
        await factoryUniV2.connect(deployer).setFeeTo(feeTo.address);
        // Create a pair.
        await factoryUniV2.connect(deployer).createPair(
            mockNative.address,
            mockERC20.address
        );
        const UniswapV2Library = await ethers.getContractFactory("UniswapV2Library");
        const uniswapV2Library = await UniswapV2Library.deploy();
        await uniswapV2Library.deployed();
        const uniV2Router = await ethers.getContractFactory(
            "UniswapV2Router02",
            { libraries: {
                UniswapV2Library: uniswapV2Library.address
            }}
        );
        routerUniV2 = await uniV2Router.connect(deployer).deploy(
            factoryUniV2.address,
            mockNative.address
        );
        await routerUniV2.deployed();
        // add initial liquidity
        await mockERC20.mintFor(user.address, ethers.utils.parseEther("100"));
        await mockNative.mint(
            user.address,
            ethers.utils.parseEther("50"),
            { value: ethers.utils.parseEther("50") }
        );
        await mockERC20.connect(user).approve(routerUniV2.address, ethers.constants.MaxUint256);
        await mockNative.connect(user).approve(routerUniV2.address, ethers.constants.MaxUint256);
        await routerUniV2.connect(user).addLiquidity(
            mockNative.address,
            mockERC20.address,
            ethers.utils.parseEther("50"),
            ethers.utils.parseEther("100"),
            0,
            0,
            user.address,
            1e10
        );

        // Deployment of the factory.
        const Bridge = await ethers.getContractFactory("BridgeWithSwap", deployer);
        bridge = (await upgrades.deployProxy(Bridge, [
            [3],
            mockNative.address,
            ethers.utils.parseEther("0.1"),
            [tokenOnSecondChain.address],
            relayer.address,
            FIVE_MINUTES
        ])) as BridgeWithSwap;
        await bridge.deployed();
        await bridge.connect(deployer).initializeSwapRouter(routerUniV2.address);
        await bridge.connect(deployer).addToken(
            mockERC20.address,
            tokenOnSecondChain.address,
            3,
            ethers.utils.parseEther("0.01"),
        );
        snapshotA = await takeSnapshot();
    });

    afterEach(async () => await snapshotA.restore());

    describe("# Send with swap", function () {
        it("Should send tokens with swap", async function () {
            const amount = ethers.utils.parseEther("1");
            const amountToExpect = ethers.utils.parseEther("0.1");
            await mockERC20.mintFor(user.address, amount);
            await mockERC20.connect(user).approve(bridge.address, amount);
            const tx = await bridge.connect(user).sendWithSwap(
                mockERC20.address,
                mockNative.address,
                user.address,
                3,
                amount,
                amountToExpect,
                1e10,
            );
            const receipt = await tx.wait();
            const event = receipt.events?.find((e) => e.event === "SendWithSwap");
            expect(event).to.not.be.undefined;
            expect(event?.args?.[0]).to.be.equal(mockERC20.address);
            expect(event?.args?.[1]).to.be.equal(mockNative.address);
            expect(event?.args?.[2]).to.be.equal(user.address);
            expect(event?.args?.[3]).to.be.equal(amount);
            expect(event?.args?.[4]).to.be.equal(amountToExpect);
            expect(event?.args?.[5]).to.be.equal(1e10);
            expect(event?.args?.[6]).to.be.equal(0);
        });

        it("Should send native with swap", async function () {
            const amount = ethers.utils.parseEther("1");
            const amountToExpect = ethers.utils.parseEther("0.1");
            const tx = await bridge.connect(user).sendWithSwap(
                mockNative.address,
                mockERC20.address,
                user.address,
                3,
                amount,
                amountToExpect,
                1e10,
                { value: amount}
            );
            const receipt = await tx.wait();
            const event = receipt.events?.find((e) => e.event === "SendWithSwap");
            expect(event).to.not.be.undefined;
            expect(event?.args?.[0]).to.be.equal(mockNative.address);
            expect(event?.args?.[1]).to.be.equal(mockERC20.address);
            expect(event?.args?.[2]).to.be.equal(user.address);
            expect(event?.args?.[3]).to.be.equal(amount);
            expect(event?.args?.[4]).to.be.equal(amountToExpect);
            expect(event?.args?.[5]).to.be.equal(1e10);
            expect(event?.args?.[6]).to.be.equal(0);
        });

        it("Should revert if amount is less than minimum", async function () {
            const amount = ethers.utils.parseEther("0.00001");
            await mockERC20.mintFor(user.address, amount);
            await mockERC20.connect(user).approve(bridge.address, amount);
            await expect(
                bridge.connect(user).sendWithSwap(
                    mockERC20.address,
                    mockNative.address,
                    user.address,
                    3,
                    amount,
                    0,
                    1e10,
                )
            ).to.be.revertedWithCustomError(bridge, "AmountIsLessThanMinimum")
                .withArgs(amount, await bridge.minAmountForToken(mockERC20.address));
        });

        it("Should revert if msg.value is not equal to amount", async function () {
            const amount = ethers.utils.parseEther("1");
            await expect(
                bridge.connect(user).sendWithSwap(
                    mockNative.address,
                    mockERC20.address,
                    user.address,
                    3,
                    amount,
                    0,
                    1e10,
                    { value: ethers.utils.parseEther("0.1")}
                )
            ).to.be.revertedWithCustomError(bridge, "AmountIsNotEqualToMsgValue")
                .withArgs(amount, ethers.utils.parseEther("0.1"));
        });

        it("Should revert if sending token with msg.value > 0", async function () {
            const amount = ethers.utils.parseEther("1");
            await mockERC20.mintFor(user.address, amount);
            await mockERC20.connect(user).approve(bridge.address, amount);
            await expect(
                bridge.connect(user).sendWithSwap(
                    mockERC20.address,
                    mockNative.address,
                    user.address,
                    3,
                    amount,
                    0,
                    1e10,
                    { value: ethers.utils.parseEther("0.1")}
                )
            ).to.be.revertedWithCustomError(bridge, "MsgValueShouldBeZero");
        });

        it("Should revert sending token if bridge is on pause", async function () {
            const amount = ethers.utils.parseEther("1");
            await mockERC20.mintFor(user.address, amount);
            await mockERC20.connect(user).approve(bridge.address, amount);
            await bridge.connect(deployer).pause();
            await expect(
                bridge.connect(user).sendWithSwap(
                    mockERC20.address,
                    mockNative.address,
                    user.address,
                    3,
                    amount,
                    0,
                    1e10,
                )
            ).to.be.revertedWith("Pausable: paused");
        });

        it("Should revert sending tokens if it is not supported", async function () {
            const MockERC20 = await ethers.getContractFactory("MockToken");
            const newMockERC20 = await MockERC20.deploy("Mock", "MCK", 18);
            await newMockERC20.deployed();
            const amount = ethers.utils.parseEther("1");
            await newMockERC20.mintFor(user.address, amount);
            await newMockERC20.connect(user).approve(bridge.address, amount);

            await expect(
                bridge.connect(user).sendWithSwap(
                    newMockERC20.address,
                    mockNative.address,
                    user.address,
                    3,
                    amount,
                    0,
                    1e10,
                )
            ).to.be.revertedWithCustomError(bridge, "TokenIsNotSupported")
                .withArgs(newMockERC20.address);
        });

        it("Should revert sending tokens if receiving chain is not supported", async function () {
            const amount = ethers.utils.parseEther("1");
            await mockERC20.mintFor(user.address, amount);
            await mockERC20.connect(user).approve(bridge.address, amount);

            await expect(
                bridge.connect(user).sendWithSwap(
                    mockERC20.address,
                    mockNative.address,
                    user.address,
                    4,
                    amount,
                    0,
                    1e10,
                )
            ).to.be.revertedWithCustomError(bridge, "ChainIsNotSupported")
                .withArgs(4);
        });
    });

    describe("# Withdraw with swap", function () {
        it("Should withdraw tokens with swap", async function () {
            const amount = ethers.utils.parseEther("1");
            const amountToExpect = ethers.utils.parseEther("0.1");
            await mockERC20.mintFor(user.address, amount);
            await mockERC20.connect(user).approve(bridge.address, amount);
            await bridge.connect(user).sendWithSwap(
                mockERC20.address,
                mockNative.address,
                user.address,
                3,
                amount,
                amountToExpect,
                1e10,
            );
            const tx = await bridge.connect(relayer).withdrawWithSwap(
                mockERC20.address,
                mockNative.address,
                user.address,
                amount,
                amountToExpect,
                3,
                0,
                1e10
            );
            const receipt = await tx.wait();
            const event = receipt.events?.find((e) => e.event === "WithdrawWithSwap");
            expect(event).to.not.be.undefined;
            expect(event?.args?.[0]).to.be.equal(mockERC20.address);
            expect(event?.args?.[1]).to.be.equal(mockNative.address);
            expect(event?.args?.[2]).to.be.equal(user.address);
            expect(event?.args?.[3]).to.be.equal(amount);
            expect(event?.args?.[4]).to.be.equal(amountToExpect);
            expect(event?.args?.[5]).to.be.equal(3);
            expect(event?.args?.[6]).to.be.equal(0);
            expect(event?.args?.[7]).to.be.equal(1e10);
        });

        it("Should withdraw native with swap", async function () {
            const amount = ethers.utils.parseEther("1");
            const amountToExpect = ethers.utils.parseEther("0.1");
            await bridge.connect(user).sendWithSwap(
                mockNative.address,
                mockERC20.address,
                user.address,
                3,
                amount,
                amountToExpect,
                1e10,
                { value: amount}
            );
            const tx = await bridge.connect(relayer).withdrawWithSwap(
                mockNative.address,
                mockERC20.address,
                user.address,
                amount,
                amountToExpect,
                3,
                0,
                1e10
            );
            const receipt = await tx.wait();
            const event = receipt.events?.find((e) => e.event === "WithdrawWithSwap");
            expect(event).to.not.be.undefined;
            expect(event?.args?.[0]).to.be.equal(mockNative.address);
            expect(event?.args?.[1]).to.be.equal(mockERC20.address);
            expect(event?.args?.[2]).to.be.equal(user.address);
            expect(event?.args?.[3]).to.be.equal(amount);
            expect(event?.args?.[4]).to.be.equal(amountToExpect);
            expect(event?.args?.[5]).to.be.equal(3);
            expect(event?.args?.[6]).to.be.equal(0);
            expect(event?.args?.[7]).to.be.equal(1e10);
        });

        it("Should withdraw tokens if sended non native tokens", async function () {
            const MockERC20 = await ethers.getContractFactory("MockToken");
            const newMockERC20 = await MockERC20.deploy("Mock", "MCK", 18);
            await newMockERC20.deployed();

            await bridge.connect(deployer).addToken(
                newMockERC20.address,
                newMockERC20.address,
                3,
                ethers.utils.parseEther("0.01"),
            );

            await newMockERC20.mintFor(user.address, ethers.utils.parseEther("100"));
            await mockNative.mint(
                user.address,
                ethers.utils.parseEther("50"),
                { value: ethers.utils.parseEther("50") }
            );
            await newMockERC20.connect(user).approve(routerUniV2.address, ethers.constants.MaxUint256);
            await mockNative.connect(user).approve(routerUniV2.address, ethers.constants.MaxUint256);
            await routerUniV2.connect(user).addLiquidity(
                mockNative.address,
                newMockERC20.address,
                ethers.utils.parseEther("50"),
                ethers.utils.parseEther("100"),
                0,
                0,
                user.address,
                1e10
            );

            const amount = ethers.utils.parseEther("1");
            const amountToExpect = ethers.utils.parseEther("0.1");
            await mockERC20.mintFor(user.address, amount);
            await mockERC20.connect(user).approve(bridge.address, amount);
            await bridge.connect(user).sendWithSwap(
                mockERC20.address,
                newMockERC20.address,
                user.address,
                3,
                amount,
                amountToExpect,
                1e10,
            );
            const tx = await bridge.connect(relayer).withdrawWithSwap(
                mockERC20.address,
                newMockERC20.address,
                user.address,
                amount,
                amountToExpect,
                3,
                0,
                1e10
            );
            const receipt = await tx.wait();
            const event = receipt.events?.find((e) => e.event === "WithdrawWithSwap");
            expect(event).to.not.be.undefined;
            expect(event?.args?.[0]).to.be.equal(mockERC20.address);
            expect(event?.args?.[1]).to.be.equal(newMockERC20.address);
            expect(event?.args?.[2]).to.be.equal(user.address);
            expect(event?.args?.[3]).to.be.equal(amount);
            expect(event?.args?.[4]).to.be.equal(amountToExpect);
            expect(event?.args?.[5]).to.be.equal(3);
            expect(event?.args?.[6]).to.be.equal(0);
            expect(event?.args?.[7]).to.be.equal(1e10);
        });

        it("Should revert if nonce is already used for withdraw", async function () {
            await mockERC20.mintFor(user.address, ethers.utils.parseEther("1"));
            await mockERC20.connect(user).approve(bridge.address, ethers.utils.parseEther("1"));
            await bridge.connect(user).sendWithSwap(
                mockERC20.address,
                mockNative.address,
                user.address,
                3,
                ethers.utils.parseEther("1"),
                ethers.utils.parseEther("0.1"),
                1e10,
            );
            await bridge.connect(relayer).withdrawWithSwap(
                mockERC20.address,
                mockNative.address,
                user.address,
                ethers.utils.parseEther("1"),
                ethers.utils.parseEther("0.1"),
                3,
                0,
                1e10
            );

            await expect(
                bridge.connect(relayer).withdrawWithSwap(
                    mockERC20.address,
                    mockNative.address,
                    user.address,
                    ethers.utils.parseEther("1"),
                    ethers.utils.parseEther("0.1"),
                    3,
                    0,
                    1e10
                )
            ).to.be.revertedWithCustomError(bridge, "NonceIsUsed")
                .withArgs(0);
        });

        it("Should revert withdraw if bridge is on pause", async function () {
            await bridge.connect(deployer).pause();
            await expect(
                bridge.connect(relayer).withdrawWithSwap(
                    mockERC20.address,
                    mockNative.address,
                    user.address,
                    ethers.utils.parseEther("1"),
                    ethers.utils.parseEther("0.1"),
                    3,
                    0,
                    1e10
                )
            ).to.be.revertedWith("Pausable: paused");
        });

        it("Should revert withdraw if caller is not a relayer", async function () {
            await expect(
                bridge.connect(user).withdrawWithSwap(
                    mockERC20.address,
                    mockNative.address,
                    user.address,
                    ethers.utils.parseEther("1"),
                    ethers.utils.parseEther("0.1"),
                    3,
                    0,
                    1e10
                )
            ).to.be.revertedWith(
                "AccessControl: account"
                +" "
                +user.address.toLocaleLowerCase()
                +" is missing role "
                +(await bridge.RELAYER_ROLE()).toLocaleLowerCase()
            );
        });

        it("Should revert withdraw if token is not supported", async function () {
            const MockERC20 = await ethers.getContractFactory("MockToken");
            const newMockERC20 = await MockERC20.deploy("Mock", "MCK", 18);
            await newMockERC20.deployed();

            await expect(
                bridge.connect(relayer).withdrawWithSwap(
                    mockNative.address,
                    newMockERC20.address,
                    user.address,
                    ethers.utils.parseEther("1"),
                    ethers.utils.parseEther("0.1"),
                    3,
                    0,
                    1e10
                )
            ).to.be.revertedWithCustomError(bridge, "TokenIsNotSupported")
                .withArgs(newMockERC20.address);
        });

        it("Should revert withdraw if chain is not supported", async function () {
            await expect(
                bridge.connect(relayer).withdrawWithSwap(
                    mockERC20.address,
                    mockNative.address,
                    user.address,
                    ethers.utils.parseEther("1"),
                    ethers.utils.parseEther("0.1"),
                    4,
                    0,
                    1e10
                )
            ).to.be.revertedWithCustomError(bridge, "ChainIsNotSupported")
                .withArgs(4);
        });

        it("Should make withdraw with swap if custom path is set", async function () {
            const MockERC20 = await ethers.getContractFactory("MockToken");
            const newMockERC20 = await MockERC20.deploy("Mock", "MCK", 18);
            await newMockERC20.deployed();

            await bridge.connect(deployer).addToken(
                newMockERC20.address,
                newMockERC20.address,
                3,
                ethers.utils.parseEther("0.01"),
            );

            await newMockERC20.mintFor(user.address, ethers.utils.parseEther("100"));
            await mockERC20.mintFor(
                user.address,
                ethers.utils.parseEther("50")
            );
            await newMockERC20.connect(user).approve(routerUniV2.address, ethers.constants.MaxUint256);
            await mockERC20.connect(user).approve(routerUniV2.address, ethers.constants.MaxUint256);
            await routerUniV2.connect(user).addLiquidity(
                mockERC20.address,
                newMockERC20.address,
                ethers.utils.parseEther("50"),
                ethers.utils.parseEther("100"),
                0,
                0,
                user.address,
                1e10
            );
            await bridge.connect(deployer).setPathForTokenToToken(
                mockERC20.address,
                newMockERC20.address,
                [mockERC20.address, newMockERC20.address]
            );
            const amount = ethers.utils.parseEther("1");
            const amountToExpect = ethers.utils.parseEther("0.1");
            await mockERC20.mintFor(user.address, amount);
            await mockERC20.connect(user).approve(bridge.address, amount);
            await bridge.connect(user).sendWithSwap(
                mockERC20.address,
                newMockERC20.address,
                user.address,
                3,
                amount,
                amountToExpect,
                1e10,
            );
            const tx = await bridge.connect(relayer).withdrawWithSwap(
                mockERC20.address,
                newMockERC20.address,
                user.address,
                amount,
                amountToExpect,
                3,
                0,
                1e10
            );
            const receipt = await tx.wait();
            const event = receipt.events?.find((e) => e.event === "WithdrawWithSwap");
            expect(event).to.not.be.undefined;
            expect(event?.args?.[0]).to.be.equal(mockERC20.address);
            expect(event?.args?.[1]).to.be.equal(newMockERC20.address);
            expect(event?.args?.[2]).to.be.equal(user.address);
            expect(event?.args?.[3]).to.be.equal(amount);
            expect(event?.args?.[4]).to.be.equal(amountToExpect);
            expect(event?.args?.[5]).to.be.equal(3);
            expect(event?.args?.[6]).to.be.equal(0);
            expect(event?.args?.[7]).to.be.equal(1e10);
        });
    });

    describe("# Utils", function () {
        it("Should revert if try to initialize swap extension second time", async function () {
            await expect(
                bridge.connect(deployer).initializeSwapRouter(
                    routerUniV2.address,
                )
            ).to.be.revertedWithCustomError(bridge, "AlreadyInitialized");
        });

        it("Should revert if non-admin tries to initialize swap extension", async function () {
            const Bridge = await ethers.getContractFactory("BridgeWithSwap", deployer);
            const newBridge = (await upgrades.deployProxy(Bridge, [
                [3],
                mockNative.address,
                ethers.utils.parseEther("0.1"),
                [tokenOnSecondChain.address],
                relayer.address,
                FIVE_MINUTES
            ])) as BridgeWithSwap;
            await newBridge.deployed();
            await expect(
                newBridge.connect(user).initializeSwapRouter(
                    routerUniV2.address,
                )
            ).to.be.revertedWith(
                "AccessControl: account"
                +" "
                +user.address.toLocaleLowerCase()
                +" is missing role "
                +(await bridge.DEFAULT_ADMIN_ROLE()).toLocaleLowerCase()
            );
        });

        it("Should revert if non-admin tries to to set path for token to token", async function () {
            await expect(
                bridge.connect(user).setPathForTokenToToken(
                    mockERC20.address,
                    mockNative.address,
                    [mockERC20.address, mockNative.address]
                )
            ).to.be.revertedWith(
                "AccessControl: account"
                +" "
                +user.address.toLocaleLowerCase()
                +" is missing role "
                +(await bridge.DEFAULT_ADMIN_ROLE()).toLocaleLowerCase()
            );
        });
    });


});
