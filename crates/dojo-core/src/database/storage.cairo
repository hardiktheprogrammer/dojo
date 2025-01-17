use core::array::{ArrayTrait, SpanTrait};
use core::option::OptionTrait;
use starknet::{SyscallResultTrait, SyscallResult};
use starknet::storage_access::{StorageAddress, StorageBaseAddress};
use core::traits::Into;
use core::poseidon::poseidon_hash_span;
use core::serde::Serde;
use dojo::packing::{pack, unpack, calculate_packed_size};

pub fn get(address_domain: u32, keys: Span<felt252>) -> felt252 {
    let base = starknet::storage_access::storage_base_address_from_felt252(
        poseidon_hash_span(keys)
    );
    starknet::syscalls::storage_read_syscall(
        address_domain, starknet::storage_access::storage_address_from_base(base)
    )
        .unwrap_syscall()
}

pub fn get_many(
    address_domain: u32, keys: Span<felt252>, mut layout: Span<u8>
) -> SyscallResult<Span<felt252>> {
    let base = starknet::storage_access::storage_base_address_from_felt252(
        poseidon_hash_span(keys)
    );
    let base_address = starknet::storage_access::storage_address_from_base(base);

    let mut packed = ArrayTrait::new();

    let mut layout_calculate = layout;
    let len: usize = calculate_packed_size(ref layout_calculate);

    let mut chunk = 0;
    let mut chunk_base = base;
    let mut index_in_chunk = 0_u8;

    let mut packed_span = loop {
        let value =
            match starknet::syscalls::storage_read_syscall(
                address_domain,
                starknet::storage_access::storage_address_from_base_and_offset(
                    chunk_base, index_in_chunk
                )
            ) {
            Result::Ok(value) => value,
            Result::Err(err) => { break SyscallResult::<Span<felt252>>::Err(err); },
        };

        packed.append(value);

        // Verify first the length to avoid computing the new chunk segment
        // if not required.
        if packed.len() == len {
            break SyscallResult::<Span<felt252>>::Ok(packed.span());
        }

        index_in_chunk = match core::integer::u8_overflowing_add(index_in_chunk, 1) {
            Result::Ok(x) => x,
            Result::Err(_) => {
                // After reading 256 `felt`s, `index_in_chunk` will overflow and we move to the
                // next chunk.
                chunk += 1;
                chunk_base = chunk_segment_pointer(base_address, chunk);
                0
            },
        };
    }?;

    let mut unpacked = ArrayTrait::new();
    unpack(ref unpacked, ref packed_span, ref layout);

    Result::Ok(unpacked.span())
}


pub fn set(address_domain: u32, keys: Span<felt252>, value: felt252) {
    let base = starknet::storage_access::storage_base_address_from_felt252(
        poseidon_hash_span(keys)
    );
    starknet::syscalls::storage_write_syscall(
        address_domain, starknet::storage_access::storage_address_from_base(base), value
    )
        .unwrap_syscall();
}

pub fn set_many(
    address_domain: u32,
    keys: Span<felt252>,
    mut unpacked: Span<felt252>,
    offset: u32,
    mut layout: Span<u8>
) -> SyscallResult<()> {
    let base = starknet::storage_access::storage_base_address_from_felt252(
        poseidon_hash_span(keys)
    );
    let base_address = starknet::storage_access::storage_address_from_base(base);

    let mut packed = ArrayTrait::new();
    pack(ref packed, ref unpacked, offset, ref layout);

    let mut chunk = 0;
    let mut chunk_base = base;
    let mut index_in_chunk = 0_u8;

    loop {
        let curr_value = match packed.pop_front() {
            Option::Some(x) => x,
            Option::None => { break Result::Ok(()); },
        };

        match starknet::syscalls::storage_write_syscall(
            address_domain,
            starknet::storage_access::storage_address_from_base_and_offset(
                chunk_base, index_in_chunk
            ),
            curr_value.into()
        ) {
            Result::Ok(_) => {},
            Result::Err(err) => { break Result::Err(err); },
        };

        index_in_chunk = match core::integer::u8_overflowing_add(index_in_chunk, 1) {
            Result::Ok(x) => x,
            Result::Err(_) => {
                // After writing 256 `felt`s, `index_in_chunk` will overflow and we move to the
                // next chunk which will be stored in an other storage segment.
                chunk += 1;
                chunk_base = chunk_segment_pointer(base_address, chunk);
                0
            },
        };
    }
}

pub fn set_packed_array(
    address_domain: u32, keys: Span<felt252>, mut data: Span<felt252>, offset: u32, array_size: u32
) -> SyscallResult<()> {
    // write data+offset by chunk of 256 felts
    let base = starknet::storage_access::storage_base_address_from_felt252(
        poseidon_hash_span(keys)
    );
    let base_address = starknet::storage_access::storage_address_from_base(base);

    let mut chunk = 0;
    let mut chunk_base = base;
    let mut index_in_chunk = 0_u8;
    let mut i = 0;

    loop {
        if i >= array_size {
            break Result::Ok(());
        }

        let curr_value = *data.at(offset + i);

        match starknet::syscalls::storage_write_syscall(
            address_domain,
            starknet::storage_access::storage_address_from_base_and_offset(
                chunk_base, index_in_chunk
            ),
            curr_value.into()
        ) {
            Result::Ok(_) => {},
            Result::Err(err) => { break Result::Err(err); },
        };

        index_in_chunk = match core::integer::u8_overflowing_add(index_in_chunk, 1) {
            Result::Ok(x) => x,
            Result::Err(_) => {
                // After writing 256 `felt`s, `index_in_chunk` will overflow and we move to the
                // next chunk which will be stored in an other storage segment.
                chunk += 1;
                chunk_base = chunk_segment_pointer(base_address, chunk);
                0
            },
        };

        i += 1;
    }
}

pub fn get_packed_array(
    address_domain: u32, keys: Span<felt252>, array_size: u32
) -> SyscallResult<Span<felt252>> {
    if array_size == 0 {
        return SyscallResult::<Span<felt252>>::Ok(array![].span());
    }

    let base = starknet::storage_access::storage_base_address_from_felt252(
        poseidon_hash_span(keys)
    );
    let base_address = starknet::storage_access::storage_address_from_base(base);

    let mut packed = ArrayTrait::new();

    let mut chunk = 0;
    let mut chunk_base = base;
    let mut index_in_chunk = 0_u8;

    loop {
        let value =
            match starknet::syscalls::storage_read_syscall(
                address_domain,
                starknet::storage_access::storage_address_from_base_and_offset(
                    chunk_base, index_in_chunk
                )
            ) {
            Result::Ok(value) => value,
            Result::Err(err) => { break SyscallResult::<Span<felt252>>::Err(err); },
        };

        packed.append(value);

        // Verify first the length to avoid computing the new chunk segment
        // if not required.
        if packed.len() == array_size {
            break Result::Ok(packed.span());
        }

        index_in_chunk = match core::integer::u8_overflowing_add(index_in_chunk, 1) {
            Result::Ok(x) => x,
            Result::Err(_) => {
                // After reading 256 `felt`s, `index_in_chunk` will overflow and we move to the
                // next chunk.
                chunk += 1;
                chunk_base = chunk_segment_pointer(base_address, chunk);
                0
            },
        };
    }
}

fn chunk_segment_pointer(address: StorageAddress, chunk: felt252) -> StorageBaseAddress {
    let p = poseidon_hash_span(array![address.into(), chunk, 'DojoStorageChunk'].span());
    starknet::storage_access::storage_base_address_from_felt252(p)
}
