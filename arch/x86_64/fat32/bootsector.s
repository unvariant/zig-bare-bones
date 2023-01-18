bios_parameter_block:
    db       0xEB, 0x3C, 0x90
original_equipment_manufacturer:
    db       "nvariant"
bytes_per_sector:
    dw       0
sectors_per_cluster:
    db       0
reserved_sectors:
    dw       0
number_of_file_allocation_tables:
    db       0
number_of_root_directories:
    dw       0
total_sectors:
    dw       0
media_descriptor_type:
    db       0
sectors_per_file_allocation_table:
    dw       0
sectors_per_track:
    dw       0
number_of_heads:
    dw       0
number_of_hidden_sectors:
    dd       0
large_sector_count:
    dd       0
extended_bios_paramter_block:
driver_number:
    db       0
reserved:
    db       0
signature:
    db       0
volume_id:
    dd       0
volume_label:
    db       "boot sector"
system_id:
    dq       0