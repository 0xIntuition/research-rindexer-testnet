CREATE EXTENSION IF NOT EXISTS plpython3u;

CREATE OR REPLACE FUNCTION keccak256(input bytea)
RETURNS text AS $$
    from eth_hash.auto import keccak
    result = keccak(bytes(input))
    return '0x' + result.hex()
$$ LANGUAGE plpython3u IMMUTABLE;

CREATE OR REPLACE FUNCTION calculateCounterTripleId(triple_id bytea)
RETURNS text AS $$
    from eth_hash.auto import keccak

    # Calculate COUNTER_SALT = keccak256("COUNTER_SALT")
    counter_salt = keccak(b"COUNTER_SALT")

    # Calculate keccak256(abi.encodePacked(COUNTER_SALT, triple_id))
    # In Solidity, abi.encodePacked just concatenates the bytes
    result = keccak(bytes(counter_salt) + bytes(triple_id))

    return '0x' + result.hex()
$$ LANGUAGE plpython3u IMMUTABLE;
