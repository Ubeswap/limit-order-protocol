const { expectRevert, constants } = require('@openzeppelin/test-helpers');
const { expect } = require('chai');

const { bufferToHex } = require('ethereumjs-util');
const ethSigUtil = require('eth-sig-util');
const Wallet = require('ethereumjs-wallet').default;

const TokenMock = artifacts.require('TokenMock');
const WrappedTokenMock = artifacts.require('WrappedTokenMock');
const LimitOrderProtocol = artifacts.require('LimitOrderProtocol');
const UbeswapOrderBook = artifacts.require('UbeswapOrderBook');
const OrderBookRewardDistributor = artifacts.require('OrderBookRewardDistributor');
const OrderBookWithFee = artifacts.require('OrderBookWithFee');
const OrderRFQBook = artifacts.require('PublicOrderRFQBook');

const { buildOrderData, buildOrderRFQData } = require('./helpers/orderUtils');
const { cutLastArg } = require('./helpers/utils');

const expectEqualOrder = (a, b) => {
    expect(a.salt).to.be.eq(b.salt);
    expect(a.makerAsset).to.be.eq(b.makerAsset);
    expect(a.takerAsset).to.be.eq(b.takerAsset);
    expect(a.maker).to.be.eq(b.maker);
    expect(a.receiver).to.be.eq(b.receiver);
    expect(a.allowedSender).to.be.eq(b.allowedSender);
    expect(a.makingAmount.toString()).to.be.eq(b.makingAmount.toString());
    expect(a.takingAmount.toString()).to.be.eq(b.takingAmount.toString());
    expect(a.makerAssetData).to.be.eq(b.makerAssetData);
    expect(a.takerAssetData).to.be.eq(b.takerAssetData);
    expect(a.getMakerData).to.be.eq(b.getMakerData);
    expect(a.getTakerData).to.be.eq(b.getTakerData);
    expect(a.predicate).to.be.eq(b.predicate);
    expect(a.permit).to.be.eq(b.permit);
    expect(a.interaction).to.be.eq(b.interaction);
};

const expectEqualOrderRFQ = (a, b) => {
    expect(a.info.toString()).to.be.eq(b.info.toString());
    expect(a.makerAsset).to.be.eq(b.makerAsset);
    expect(a.takerAsset).to.be.eq(b.takerAsset);
    expect(a.maker).to.be.eq(b.maker);
    expect(a.allowedSender).to.be.eq(b.allowedSender);
    expect(a.makingAmount.toString()).to.be.eq(b.makingAmount.toString());
    expect(a.takingAmount.toString()).to.be.eq(b.takingAmount.toString());
};

describe('OrderBooks', async function () {
    let addr1, addr2, wallet;

    const privatekey = '59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d';
    const account = Wallet.fromPrivateKey(Buffer.from(privatekey, 'hex'));

    function buildOrder (
        exchange,
        makerAsset,
        takerAsset,
        makingAmount,
        takingAmount,
        allowedSender = constants.ZERO_ADDRESS,
        predicate = '0x',
        permit = '0x',
        interaction = '0x',
        receiver = constants.ZERO_ADDRESS,
    ) {
        return buildOrderWithSalt(exchange, '1', makerAsset, takerAsset, makingAmount, takingAmount, allowedSender, predicate, permit, interaction, receiver);
    }

    function buildOrderWithSalt (
        exchange,
        salt,
        makerAsset,
        takerAsset,
        makingAmount,
        takingAmount,
        allowedSender = constants.ZERO_ADDRESS,
        predicate = '0x',
        permit = '0x',
        interaction = '0x',
        receiver = constants.ZERO_ADDRESS,
    ) {
        return {
            salt: salt,
            makerAsset: makerAsset.address,
            takerAsset: takerAsset.address,
            maker: wallet,
            receiver,
            allowedSender,
            makingAmount,
            takingAmount,
            makerAssetData: '0x',
            takerAssetData: '0x',
            getMakerAmount: cutLastArg(exchange.contract.methods.getMakerAmount(makingAmount, takingAmount, 0).encodeABI()),
            getTakerAmount: cutLastArg(exchange.contract.methods.getTakerAmount(makingAmount, takingAmount, 0).encodeABI()),
            predicate: predicate,
            permit: permit,
            interaction: interaction,
        };
    }

    function buildOrderRFQ (info, makerAsset, takerAsset, makingAmount, takingAmount, allowedSender = constants.ZERO_ADDRESS) {
        return {
            info,
            makerAsset: makerAsset.address,
            takerAsset: takerAsset.address,
            maker: wallet,
            allowedSender,
            makingAmount,
            takingAmount,
        };
    }

    before(async function () {
        [addr1, wallet, addr2] = await web3.eth.getAccounts();
    });

    beforeEach(async function () {
        this.dai = await TokenMock.new('DAI', 'DAI');
        this.weth = await WrappedTokenMock.new('WETH', 'WETH');
        this.ube = await TokenMock.new('UBE', 'UBE');

        this.swap = await LimitOrderProtocol.new();
        this.rewardDistributor = await OrderBookRewardDistributor.new(this.ube.address);
        this.ubeswapOrderBook = await UbeswapOrderBook.new(this.swap.address, 500, addr2, this.rewardDistributor.address);
        this.orderBook = await OrderBookWithFee.new(this.swap.address);
        this.orderRFQBook = await OrderRFQBook.new(this.swap.address);

        // We get the chain id from the contract because Ganache (used for coverage) does not return the same chain id
        // from within the EVM as from the JSON RPC interface.
        // See https://github.com/trufflesuite/ganache-core/issues/515
        this.chainId = await this.dai.getChainId();
        this.ube.mint(this.rewardDistributor.address, 1_000_000);
        this.rewardDistributor.addToWhitelist(this.ubeswapOrderBook.address);
    });

    describe('OrderBookWithFee', async function () {
        it('broadcasts w/ fee', async function () {
            const makingAmount = 10_000;
            const order = buildOrder(this.swap, this.dai, this.weth, makingAmount, 1);
            const data = buildOrderData(this.chainId, this.swap.address, order);
            const signature = ethSigUtil.signTypedMessage(account.getPrivateKey(), { data });
            const orderHash = bufferToHex(ethSigUtil.TypedDataUtils.sign(data));

            const expectedFee = '5';
            await this.dai.mint(addr1, expectedFee);
            await this.dai.approve(this.orderBook.address, expectedFee);

            expect((await this.dai.balanceOf(addr1)).toString()).to.be.eq(expectedFee);
            expect((await this.dai.balanceOf(addr2)).toString()).to.be.eq('0');
            // 5 bps to `addr2`
            const { logs } = await this.orderBook.broadcastOrder(order, signature, 500, addr2);
            expect(logs.length).to.be.eq(1);
            expect(logs[0].args.maker).to.be.eq(wallet);
            expect(logs[0].args.orderHash).to.be.eq(orderHash);
            expectEqualOrder(logs[0].args.order, order);
            expect(logs[0].args.signature).to.be.eq(signature);

            expect((await this.dai.balanceOf(addr1)).toString()).to.be.eq('0');
            expect((await this.dai.balanceOf(addr2)).toString()).to.be.eq(expectedFee);
        });

        it('fail to broadcast if signature is invalid', async function () {
            const order = buildOrder(this.swap, this.dai, this.weth, 1, 1);
            const data = buildOrderData(this.chainId, this.swap.address, order);
            const signature = ethSigUtil.signTypedMessage(account.getPrivateKey(), { data });
            const anotherOrder = buildOrder(this.swap, this.dai, this.weth, 1, 2);
            await expectRevert(this.orderBook.broadcastOrder(anotherOrder, signature, 5, addr2), 'OB: bad signature');
        });
    });

    describe('UbeswapOrderBook', async function () {
        it('broadcasts w/ fee', async function () {
            const makingAmount = 10_000;
            const order = buildOrder(this.swap, this.dai, this.weth, makingAmount, 1);
            const data = buildOrderData(this.chainId, this.swap.address, order);
            const signature = ethSigUtil.signTypedMessage(account.getPrivateKey(), { data });
            const orderHash = bufferToHex(ethSigUtil.TypedDataUtils.sign(data));

            const expectedFee = '5';
            await this.dai.mint(addr1, expectedFee);
            await this.dai.approve(this.ubeswapOrderBook.address, expectedFee);

            expect((await this.dai.balanceOf(addr1)).toString()).to.be.eq(expectedFee);
            expect((await this.dai.balanceOf(addr2)).toString()).to.be.eq('0');
            // 5 bps to `addr2`
            const { logs } = await this.ubeswapOrderBook.broadcastOrder(order, signature);
            expect(logs.length).to.be.eq(1);
            expect(logs[0].args.maker).to.be.eq(wallet);
            expect(logs[0].args.orderHash).to.be.eq(orderHash);
            expectEqualOrder(logs[0].args.order, order);
            expect(logs[0].args.signature).to.be.eq(signature);

            expect((await this.dai.balanceOf(addr1)).toString()).to.be.eq('0');
            expect((await this.dai.balanceOf(addr2)).toString()).to.be.eq(expectedFee);
        });

        it('broadcasts w/ fee and reward', async function () {
            const makingAmount = 10_000;
            const order = buildOrder(this.swap, this.dai, this.weth, makingAmount, 1);
            const data = buildOrderData(this.chainId, this.swap.address, order);
            const signature = ethSigUtil.signTypedMessage(account.getPrivateKey(), { data });
            const orderHash = bufferToHex(ethSigUtil.TypedDataUtils.sign(data));

            const expectedFee = '5';
            await this.dai.mint(addr1, expectedFee);
            await this.dai.approve(this.ubeswapOrderBook.address, expectedFee);

            // Enable subsidies on DAI
            const expectedReward = '5';
            await this.rewardDistributor.changeRewardRate(this.dai.address, 500);

            expect((await this.dai.balanceOf(addr1)).toString()).to.be.eq(expectedFee);
            expect((await this.dai.balanceOf(addr2)).toString()).to.be.eq('0');
            expect((await this.ube.balanceOf(addr1)).toString()).to.be.eq('0');
            // 5 bps to `addr2`
            const { logs } = await this.ubeswapOrderBook.broadcastOrder(order, signature);
            expect(logs.length).to.be.eq(1);
            expect(logs[0].args.maker).to.be.eq(wallet);
            expect(logs[0].args.orderHash).to.be.eq(orderHash);
            expectEqualOrder(logs[0].args.order, order);
            expect(logs[0].args.signature).to.be.eq(signature);

            expect((await this.dai.balanceOf(addr1)).toString()).to.be.eq('0');
            expect((await this.dai.balanceOf(addr2)).toString()).to.be.eq(expectedFee);
            expect((await this.ube.balanceOf(addr1)).toString()).to.be.eq(expectedReward);
        });
        
        it('reverts if EOA calls distribute reward', async function () {
            // Test changing reward currency
            const order = buildOrder(this.swap, this.dai, this.weth, 10_000, 1);
            await expectRevert(this.rewardDistributor.distributeReward(order, addr1), 'Whitelistable: caller not whitelisted');
        });

        it('change reward values', async function () {
            // Test changing reward currency
            expect(await this.rewardDistributor.rewardCurrency()).to.be.eq(this.ube.address);
            await this.rewardDistributor.changeRewardCurrency(this.dai.address);
            expect(await this.rewardDistributor.rewardCurrency()).to.be.eq(this.dai.address);
            await expectRevert(this.rewardDistributor.changeRewardCurrency(this.ube.address, { from: wallet }), 'Ownable: caller is not the owner');

            // Test changing reward rate
            expect((await this.rewardDistributor.rewardRate(this.dai.address)).toString()).to.be.eq('0');
            await this.rewardDistributor.changeRewardRate(this.dai.address, 500);
            expect((await this.rewardDistributor.rewardRate(this.dai.address)).toString()).to.be.eq('500');
            await expectRevert(this.rewardDistributor.changeRewardRate(this.dai.address, 0, { from: wallet }), 'Ownable: caller is not the owner');
        });

        it('rescues ERC20', async function () {
            const contractBalance = (await this.ube.balanceOf(this.rewardDistributor.address)).toString();
            expect((await this.ube.balanceOf(addr1)).toString()).to.be.eq('0');
            await expectRevert(this.rewardDistributor.rescueERC20(this.ube.address, contractBalance, { from: wallet }), 'Ownable: caller is not the owner');
            await this.rewardDistributor.rescueERC20(this.ube.address, contractBalance);
            expect((await this.ube.balanceOf(addr1)).toString()).to.be.eq(contractBalance);
        });

        it('fail to broadcast if signature is invalid', async function () {
            const order = buildOrder(this.swap, this.dai, this.weth, 1, 1);
            const data = buildOrderData(this.chainId, this.swap.address, order);
            const signature = ethSigUtil.signTypedMessage(account.getPrivateKey(), { data });
            const anotherOrder = buildOrder(this.swap, this.dai, this.weth, 1, 2);
            await expectRevert(this.ubeswapOrderBook.broadcastOrder(anotherOrder, signature), 'OB: bad signature');
        });
    });

    describe('Broadcast OrderRFQ', async function () {
        it('broadcast', async function () {
            const order = buildOrderRFQ('20203181441137406086353707335681', this.dai, this.weth, 1, 1);
            const data = buildOrderRFQData(this.chainId, this.swap.address, order);
            const signature = ethSigUtil.signTypedMessage(account.getPrivateKey(), { data });
            const orderHash = bufferToHex(ethSigUtil.TypedDataUtils.sign(data));

            const { logs } = await this.orderRFQBook.broadcastOrderRFQ(order, signature);
            expect(logs.length).to.be.eq(1);
            expect(logs[0].args.maker).to.be.eq(wallet);
            expect(logs[0].args.orderHash).to.be.eq(orderHash);
            expectEqualOrderRFQ(logs[0].args.order, order);
            expect(logs[0].args.signature).to.be.eq(signature);
        });

        it('fail to broadcast if signature is invalid', async function () {
            const order = buildOrderRFQ('20203181441137406086353707335681', this.dai, this.weth, 1, 1);
            const data = buildOrderRFQData(this.chainId, this.swap.address, order);
            const signature = ethSigUtil.signTypedMessage(account.getPrivateKey(), { data });
            const anotherOrder = buildOrderRFQ('10203181441137406086353707335681', this.dai, this.weth, 1, 1);
            await expectRevert(this.orderRFQBook.broadcastOrderRFQ(anotherOrder, signature), 'OB: bad signature');
        });
    });
});
