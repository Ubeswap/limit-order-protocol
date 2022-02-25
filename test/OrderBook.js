const { expectRevert, constants } = require('@openzeppelin/test-helpers');
const { expect } = require('chai');

const { bufferToHex } = require('ethereumjs-util');
const ethSigUtil = require('eth-sig-util');
const Wallet = require('ethereumjs-wallet').default;

const TokenMock = artifacts.require('TokenMock');
const WrappedTokenMock = artifacts.require('WrappedTokenMock');
const LimitOrderProtocol = artifacts.require('LimitOrderProtocol');
const UbeswapOrderBook = artifacts.require('UbeswapOrderBook');
const OrderRFQBook = artifacts.require('OrderRFQBook');

const { buildOrderData, buildOrderRFQData } = require('./helpers/orderUtils');
const { cutLastArg, toBN } = require('./helpers/utils');
const { ZERO_ADDRESS } = require('@openzeppelin/test-helpers/src/constants');

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

describe('UbeswapOrderBook', async function () {
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

        this.swap = await LimitOrderProtocol.new();
        this.orderBook = await UbeswapOrderBook.new(this.swap.address, 0, ZERO_ADDRESS);
        this.orderRFQBook = await OrderRFQBook.new(this.swap.address);

        // We get the chain id from the contract because Ganache (used for coverage) does not return the same chain id
        // from within the EVM as from the JSON RPC interface.
        // See https://github.com/trufflesuite/ganache-core/issues/515
        this.chainId = await this.dai.getChainId();
    });

    describe('Broadcast Order', async function () {
        it('broadcast', async function () {
            const order = buildOrder(this.swap, this.dai, this.weth, 1, 1);
            const data = buildOrderData(this.chainId, this.swap.address, order);
            const signature = ethSigUtil.signTypedMessage(account.getPrivateKey(), { data });
            const orderHash = bufferToHex(ethSigUtil.TypedDataUtils.sign(data));

            const { logs } = await this.orderBook.broadcastOrder(order, signature);
            expect(logs.length).to.be.eq(1);
            expect(logs[0].args.maker).to.be.eq(wallet);
            expect(logs[0].args.orderHash).to.be.eq(orderHash);

            const fetchedOrder = await this.orderBook.orders(orderHash);
            const fetchedSignature = await this.orderBook.signatures(orderHash);
            expectEqualOrder(order, fetchedOrder);
            expect(fetchedSignature).to.be.eq(signature);
        });

        it('broadcasts w/ fee', async function () {
            // 5 bps to `addr2`
            await this.orderBook.changeFee(5);
            await this.orderBook.changeFeeRecipient(addr2);

            const makingAmount = 10_000;
            const order = buildOrder(this.swap, this.dai, this.weth, makingAmount, 1);
            const data = buildOrderData(this.chainId, this.swap.address, order);
            const signature = ethSigUtil.signTypedMessage(account.getPrivateKey(), { data });

            const expectedFee = 50;
            await this.dai.mint(addr1, 50);
            await this.dai.approve(this.orderBook.address, expectedFee);

            expect((await this.dai.balanceOf(addr1)).toString()).to.be.eq('50');
            expect((await this.dai.balanceOf(addr2)).toString()).to.be.eq('0');
            await this.orderBook.broadcastOrder(order, signature);
            expect((await this.dai.balanceOf(addr1)).toString()).to.be.eq('0');
            expect((await this.dai.balanceOf(addr2)).toString()).to.be.eq('50');
        });

        it('fail to broadcast if signature is invalid', async function () {
            const order = buildOrder(this.swap, this.dai, this.weth, 1, 1);
            const data = buildOrderData(this.chainId, this.swap.address, order);
            const signature = ethSigUtil.signTypedMessage(account.getPrivateKey(), { data });
            const anotherOrder = buildOrder(this.swap, this.dai, this.weth, 1, 2);
            await expectRevert(this.orderBook.broadcastOrder(anotherOrder, signature), 'OB: bad signature');
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

            const fetchedOrder = await this.orderRFQBook.orderRFQs(orderHash);
            const fetchedSignature = await this.orderRFQBook.signatures(orderHash);
            expectEqualOrderRFQ(order, fetchedOrder);
            expect(fetchedSignature).to.be.eq(signature);
        });

        it('fail to broadcast if signature is invalid', async function () {
            const order = buildOrderRFQ('20203181441137406086353707335681', this.dai, this.weth, 1, 1);
            const data = buildOrderRFQData(this.chainId, this.swap.address, order);
            const signature = ethSigUtil.signTypedMessage(account.getPrivateKey(), { data });
            const anotherOrder = buildOrderRFQ('10203181441137406086353707335681', this.dai, this.weth, 1, 1);
            await expectRevert(this.orderRFQBook.broadcastOrderRFQ(anotherOrder, signature), 'OB: bad signature');
        });
    });

    describe('changeFee', () => {
        it('can only be changed by owner', async function () {
            expect((await this.orderBook.fee()).toString()).to.be.equal('0');
            await expectRevert(this.orderBook.changeFee(5, { from: wallet }), 'Ownable: caller is not the owner');
            await this.orderBook.changeFee(5);
            expect((await this.orderBook.fee()).toString()).to.be.equal('5');
        });
    });

    describe('changeFeeRecipient', () => {
        it('can only be changed by owner', async function () {
            expect(await this.orderBook.feeRecipient()).to.be.equal(ZERO_ADDRESS);
            await expectRevert(this.orderBook.changeFeeRecipient(addr1, { from: wallet }), 'Ownable: caller is not the owner');
            await this.orderBook.changeFeeRecipient(addr1);
            expect(await this.orderBook.feeRecipient()).to.be.equal(addr1);
        });
    });
});
