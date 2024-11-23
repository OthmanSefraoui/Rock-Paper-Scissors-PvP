from poseidon_py.poseidon_hash import (
    poseidon_perm,
    poseidon_hash_func,
    poseidon_hash,
    poseidon_hash_single,
    poseidon_hash_many,
)

# Define the Poseidon hash parameters

# Inputs for the hash
move = 1  # Example: Paper
secret = 1  # Random secret for commitment

# Compute the Poseidon hash
commitment = poseidon_hash_many([move, secret])

print("Poseidon Hash (Decimal):", commitment)
print("Poseidon Hash (Hex):", hex(commitment))
