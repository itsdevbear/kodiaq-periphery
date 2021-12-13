pragma solidity >=0.5.0;

interface IKodiaqMigrator {
    function migrate(address token, uint amountTokenMin, uint amountBERAMin, address to, uint deadline) external;
}
