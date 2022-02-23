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

    const orderBook = await deploy('OrderBook', {
        from: deployer,
        args: [limitOrderProtocol.address],
    });

    console.log('OrderBook deployed to:', orderBook.address);

    const orderRFQBook = await deploy('OrderRFQBook', {
        from: deployer,
        args: [limitOrderProtocol.address],
    });

    console.log('OrderRFQBook deployed to:', orderRFQBook.address);

    if (!noVerify.includes(await getChainId())) {
        await hre.run('verify:verify', {
            address: limitOrderProtocol.address,
        });
    }
};

module.exports.skip = async () => true;
