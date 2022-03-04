const hre = require('hardhat');
const { getChainId } = hre;

const noVerify = ['31337', '44787', '42220'];

module.exports = async ({ getNamedAccounts, deployments }) => {
    console.log('running deploy script');
    console.log('network id ', await getChainId());

    const { deploy } = deployments;
    const { deployer } = await getNamedAccounts();

    const limitOrderProtocol = await deploy('LimitOrderProtocol', {
        from: deployer,
    });

    console.log('LimitOrderProtocol deployed to:', limitOrderProtocol.address);

    const orderBook = await deploy('OrderBookWithFee', {
        from: deployer,
        args: [limitOrderProtocol.address],
    });

    console.log('OrderBookWithFee deployed to:', orderBook.address);

    const ubeswapOrderBook = await deploy('UbeswapOrderBook', {
        from: deployer,
        args: [limitOrderProtocol.address, 500, '0x97A9681612482A22b7877afbF8430EDC76159Cae'],
    });

    console.log('UbeswapOrderBook deployed to:', ubeswapOrderBook.address);

    if (!noVerify.includes(await getChainId())) {
        await hre.run('verify:verify', {
            address: limitOrderProtocol.address,
        });
    }
};

module.exports.skip = async () => false;
