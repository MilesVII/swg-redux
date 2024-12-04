package nbnet

NBN_Allocator :: `malloc`
NBN_Reallocator :: `realloc`
NBN_Deallocator :: `free`
NBN_Abort :: `abort`
NBN_ERROR :: -1
WORD_BYTES :: `(sizeof(Word))`
WORD_BITS :: `((sizeof(Word)) * 8)`
NBN_MAX_CHANNELS :: 8
NBN_LIBRARY_RESERVED_CHANNELS :: 3
NBN_MAX_MESSAGE_TYPES :: 255
NBN_MESSAGE_RESEND_DELAY :: 0.1000000000000000
NIST_B163 :: 1
NIST_K163 :: 2
NIST_B233 :: 3
NIST_K233 :: 4
NIST_B283 :: 5
NIST_K283 :: 6
NIST_B409 :: 7
NIST_K409 :: 8
NIST_B571 :: 9
NIST_K571 :: 10
ECC_CURVE :: 3
CURVE_DEGREE :: 233
ECC_PRV_KEY_SIZE :: 32
ECC_PUB_KEY_SIZE :: `(2 * 32)`
AES128 :: 1
AES_BLOCKLEN :: 16
AES_KEYLEN :: 16
AES_keyExpSize :: 176
POLY1305_KEYLEN :: 32
POLY1305_TAGLEN :: 16
NBN_RPC_MAX_PARAM_COUNT :: 16
NBN_RPC_MAX :: 32
NBN_RPC_STRING_MAX_LENGTH :: 256
NBN_PACKET_MAX_SIZE :: 1400
NBN_MAX_MESSAGES_PER_PACKET :: 255
NBN_PACKET_HEADER_SIZE :: `sizeof(NBN_PacketHeader)`
NBN_PACKET_MAX_DATA_SIZE :: `(1400 - sizeof(NBN_PacketHeader))`
NBN_PACKET_MAX_USER_DATA_SIZE :: `((1400 - sizeof(NBN_PacketHeader)) - 16)`
NBN_MESSAGE_CHUNK_SIZE :: `(((1400 - sizeof(NBN_PacketHeader)) - 16) - sizeof(NBN_MessageHeader) - 2)`
NBN_MESSAGE_CHUNK_TYPE :: `(255 - 1)`
NBN_CLIENT_CLOSED_MESSAGE_TYPE :: `(255 - 2)`
NBN_CLIENT_ACCEPTED_MESSAGE_TYPE :: `(255 - 3)`
NBN_SERVER_DATA_MAX_SIZE :: 1024
NBN_CONNECTION_DATA_MAX_SIZE :: 512
NBN_BYTE_ARRAY_MESSAGE_TYPE :: `(255 - 4)`
NBN_BYTE_ARRAY_MAX_SIZE :: 4096
NBN_PUBLIC_CRYPTO_INFO_MESSAGE_TYPE :: `(255 - 5)`
NBN_START_ENCRYPT_MESSAGE_TYPE :: `(255 - 6)`
NBN_DISCONNECTION_MESSAGE_TYPE :: `(255 - 7)`
NBN_CONNECTION_REQUEST_MESSAGE_TYPE :: `(255 - 8)`
NBN_RPC_MESSAGE_TYPE :: `(255 - 9)`
NBN_CHANNEL_BUFFER_SIZE :: 1024
NBN_CHANNEL_CHUNKS_BUFFER_SIZE :: 255
NBN_CHANNEL_RW_CHUNK_BUFFER_INITIAL_SIZE :: 2048
NBN_CHANNEL_OUTGOING_MESSAGE_POOL_SIZE :: 512
NBN_CHANNEL_RESERVED_UNRELIABLE :: `(8 - 1)`
NBN_CHANNEL_RESERVED_RELIABLE :: `(8 - 2)`
NBN_CHANNEL_RESERVED_LIBRARY_MESSAGES :: `(8 - 3)`
NBN_MAX_PACKET_ENTRIES :: 1024
NBN_CONNECTION_MAX_SENT_PACKET_COUNT :: 16
NBN_CONNECTION_STALE_TIME_THRESHOLD :: 3
NBN_NO_EVENT :: 0
NBN_SKIP_EVENT :: 1
NBN_EVENT_QUEUE_CAPACITY :: 1024
NBN_MAX_CLIENTS :: 1024
NBN_MAX_DRIVERS :: 4

NBN_Connection :: ^^^rawptr
NBN_MessageHeader :: struct {
    id: u16,
    type: u8,
    channel_id: u8,
}
NBN_OutgoingMessage :: struct {
    type: u8,
    ref_count: u32,
    data: rawptr,
}
NBN_Message :: struct {
    header: NBN_MessageHeader,
    sender: ^NBN_Connection,
    outgoing_msg: ^NBN_OutgoingMessage,
    data: rawptr,
}
NBN_MessageSlot :: struct {
    message: NBN_Message,
    last_send_time: f64,
    free: b8,
}
NBN_MessageChunk :: struct {
    id: u8,
    total: u8,
    data: [1346]u8,
    outgoing_msg: ^NBN_OutgoingMessage,
}
NBN_Channel :: struct {
    id: u8,
    write_chunk_buffer: ^u8,
    next_outgoing_message_id: u16,
    next_recv_message_id: u16,
    next_outgoing_message_pool_slot: u32,
    outgoing_message_count: u32,
    chunk_count: u32,
    write_chunk_buffer_size: u32,
    read_chunk_buffer_size: u32,
    next_outgoing_chunked_message: u32,
    last_received_chunk_id: i32,
    read_chunk_buffer: ^u8,
    destructor: NBN_ChannelDestructor,
    connection: ^NBN_Connection,
    outgoing_message_slot_buffer: [1024]NBN_MessageSlot,
    recved_message_slot_buffer: [1024]NBN_MessageSlot,
    recv_chunk_buffer: ^[255]^NBN_MessageChunk,
    outgoing_message_pool: [512]NBN_OutgoingMessage,
    AddReceivedMessage: AddReceivedMessage_func_ptr_anon_0,
    AddOutgoingMessage: AddOutgoingMessage_func_ptr_anon_1,
    GetNextRecvedMessage: GetNextRecvedMessage_func_ptr_anon_2,
    GetNextOutgoingMessage: GetNextOutgoingMessage_func_ptr_anon_3,
    OnOutgoingMessageAcked: OnOutgoingMessageAcked_func_ptr_anon_4,
    OnOutgoingMessageSent: OnOutgoingMessageSent_func_ptr_anon_5,
}
NBN_ChannelBuilder :: #type proc "c" () -> ^NBN_Channel
NBN_ChannelDestructor :: #type proc "c" (param0: ^NBN_Channel)
NBN_MessageBuilder :: #type proc "c" () -> rawptr
NBN_MessageDestructor :: #type proc "c" (param0: rawptr)
NBN_StreamType :: enum i32 {NBN_STREAM_WRITE = 0, NBN_STREAM_READ = 1, NBN_STREAM_MEASURE = 2, }
NBN_Stream :: struct {
    type: NBN_StreamType,
    serialize_uint_func: NBN_Stream_SerializeUInt,
    serialize_uint64_func: NBN_Stream_SerializeUInt64,
    serialize_int_func: NBN_Stream_SerializeInt,
    serialize_float_func: NBN_Stream_SerializeFloat,
    serialize_bool_func: NBN_Stream_SerializeBool,
    serialize_padding_func: NBN_Stream_SerializePadding,
    serialize_bytes_func: NBN_Stream_SerializeBytes,
}
NBN_MessageSerializer :: #type proc "c" (param0: rawptr, param1: ^NBN_Stream) -> i32
NBN_ConnectionHandle :: u32
NBN_MessageInfo :: struct {
    type: u8,
    channel_id: u8,
    data: rawptr,
    sender: NBN_ConnectionHandle,
}
NBN_EventData :: struct #raw_union {message_info: NBN_MessageInfo, connection: ^NBN_Connection, connection_handle: NBN_ConnectionHandle, }
NBN_Event :: struct {
    type: i32,
    data: NBN_EventData,
}
NBN_EventQueue :: struct {
    events: [1024]NBN_Event,
    head: u32,
    tail: u32,
    count: u32,
}
NBN_RPC_ParamType :: enum i32 {NBN_RPC_PARAM_INT = 0, NBN_RPC_PARAM_FLOAT = 1, NBN_RPC_PARAM_BOOL = 2, NBN_RPC_PARAM_STRING = 3, }
NBN_RPC_Signature :: struct {
    param_count: u32,
    params: [16]NBN_RPC_ParamType,
}
NBN_RPC_ParamValue :: struct #raw_union {i: i32, f: f32, b: b8, s: [256]i8, }
NBN_RPC_Param :: struct {
    type: NBN_RPC_ParamType,
    value: NBN_RPC_ParamValue,
}
NBN_RPC_Func :: #type proc "c" (param0: u32, param1: [16]NBN_RPC_Param, sender: NBN_ConnectionHandle)
NBN_RPC :: struct {
    id: u32,
    signature: NBN_RPC_Signature,
    func: NBN_RPC_Func,
}
NBN_Endpoint :: struct {
    channel_builders: [8]NBN_ChannelBuilder,
    channel_destructors: [8]NBN_ChannelDestructor,
    message_builders: [255]NBN_MessageBuilder,
    message_destructors: [255]NBN_MessageDestructor,
    message_serializers: [255]NBN_MessageSerializer,
    event_queue: NBN_EventQueue,
    rpcs: [32]NBN_RPC,
    is_server: b8,
    time: f64,
}
NBN_Driver_ClientStartFunc :: #type proc "c" (param0: u32, param1: cstring, param2: u16, param3: b8) -> i32
NBN_Driver_StopFunc :: #type proc "c" ()
NBN_Driver_RecvPacketsFunc :: #type proc "c" () -> i32
NBN_PacketHeader :: struct {
    protocol_id: u32,
    seq_number: u16,
    ack: u16,
    ack_bits: u32,
    messages_count: u8,
    is_encrypted: u8,
    auth_tag: [16]u8,
}
NBN_PacketMode :: enum i32 {NBN_PACKET_MODE_WRITE = 1, NBN_PACKET_MODE_READ = 2, }
NBN_BitWriter :: struct {
    size: u32,
    buffer: ^u8,
    scratch: u64,
    scratch_bits_count: u32,
    byte_cursor: u32,
}
NBN_WriteStream :: struct {
    base: NBN_Stream,
    bit_writer: NBN_BitWriter,
}
NBN_BitReader :: struct {
    size: u32,
    buffer: ^u8,
    scratch: u64,
    scratch_bits_count: u32,
    byte_cursor: u32,
}
NBN_ReadStream :: struct {
    base: NBN_Stream,
    bit_reader: NBN_BitReader,
}
NBN_MeasureStream :: struct {
    base: NBN_Stream,
    number_of_bits: u32,
}
NBN_Packet :: struct {
    header: NBN_PacketHeader,
    mode: NBN_PacketMode,
    sender: ^NBN_Connection,
    buffer: [1400]u8,
    size: u32,
    sealed: b8,
    w_stream: NBN_WriteStream,
    r_stream: NBN_ReadStream,
    m_stream: NBN_MeasureStream,
    aes_iv: [16]u8,
}
NBN_Driver_ClientSendPacketFunc :: #type proc "c" (param0: ^NBN_Packet) -> i32
NBN_Driver_ServerStartFunc :: #type proc "c" (param0: u32, param1: u16, param2: b8) -> i32
NBN_Driver_ServerSendPacketToFunc :: #type proc "c" (param0: ^NBN_Packet, param1: ^NBN_Connection) -> i32
NBN_Driver_ServerRemoveConnection :: #type proc "c" (param0: ^NBN_Connection)
NBN_DriverImplementation :: struct {
    cli_start: NBN_Driver_ClientStartFunc,
    cli_stop: NBN_Driver_StopFunc,
    cli_recv_packets: NBN_Driver_RecvPacketsFunc,
    cli_send_packet: NBN_Driver_ClientSendPacketFunc,
    serv_start: NBN_Driver_ServerStartFunc,
    serv_stop: NBN_Driver_StopFunc,
    serv_recv_packets: NBN_Driver_RecvPacketsFunc,
    serv_send_packet_to: NBN_Driver_ServerSendPacketToFunc,
    serv_remove_connection: NBN_Driver_ServerRemoveConnection,
}
NBN_Driver :: struct {
    id: i32,
    name: cstring,
    impl: NBN_DriverImplementation,
}
NBN_ConnectionVector :: struct {
    connections: ^[^]NBN_Connection,
    count: u32,
    capacity: u32,
}
NBN_ConnectionTable :: struct {
    connections: ^[^]NBN_Connection,
    capacity: u32,
    count: u32,
    load_factor: f32,
}
NBN_MemPoolFreeBlock :: struct {
    next: ^NBN_MemPoolFreeBlock,
}
NBN_MemPool :: struct {
    blocks: ^[^]u8,
    block_size: u64,
    block_count: u32,
    block_idx: u32,
    free: ^NBN_MemPoolFreeBlock,
}
NBN_MemoryManager :: struct {
    mem_pools: [16]NBN_MemPool,
}
Word :: u32
NBN_Stream_SerializeUInt :: #type proc "c" (param0: ^NBN_Stream, param1: ^u32, param2: u32, param3: u32) -> i32
NBN_Stream_SerializeUInt64 :: #type proc "c" (param0: ^NBN_Stream, param1: ^u64) -> i32
NBN_Stream_SerializeInt :: #type proc "c" (param0: ^NBN_Stream, param1: ^i32, param2: i32, param3: i32) -> i32
NBN_Stream_SerializeFloat :: #type proc "c" (param0: ^NBN_Stream, param1: ^f32, param2: f32, param3: f32, param4: i32) -> i32
NBN_Stream_SerializeBool :: #type proc "c" (param0: ^NBN_Stream, param1: ^b8) -> i32
NBN_Stream_SerializePadding :: #type proc "c" (param0: ^NBN_Stream) -> i32
NBN_Stream_SerializeBytes :: #type proc "c" (param0: ^NBN_Stream, param1: ^u8, param2: u32) -> i32
AES_ctx :: struct {
    RoundKey: [176]u8,
    Iv: [16]u8,
}
CSPRNG :: rawptr
NBN_RPC_String :: struct {
    string_m: [256]i8,
    length: u32,
}
NBN_ClientClosedMessage :: struct {
    code: i32,
}
NBN_ClientAcceptedMessage :: struct {
    length: u32,
    data: [1024]u8,
}
NBN_ByteArrayMessage :: struct {
    bytes: [4096]u8,
    length: u32,
}
NBN_PublicCryptoInfoMessage :: struct {
    pub_key1: [64]u8,
    pub_key2: [64]u8,
    pub_key3: [64]u8,
    aes_iv: [16]u8,
}
NBN_ConnectionRequestMessage :: struct {
    length: u32,
    data: [512]u8,
}
NBN_RPC_Message :: struct {
    id: u32,
    param_count: u32,
    params: [16]NBN_RPC_Param,
}
AddReceivedMessage_func_ptr_anon_0 :: #type proc "c" (param0: ^NBN_Channel, param1: ^NBN_Message) -> b8
AddOutgoingMessage_func_ptr_anon_1 :: #type proc "c" (param0: ^NBN_Channel, param1: ^NBN_Message) -> b8
GetNextRecvedMessage_func_ptr_anon_2 :: #type proc "c" (param0: ^NBN_Channel) -> ^NBN_Message
GetNextOutgoingMessage_func_ptr_anon_3 :: #type proc "c" (param0: ^NBN_Channel, param1: f64) -> ^NBN_Message
OnOutgoingMessageAcked_func_ptr_anon_4 :: #type proc "c" (param0: ^NBN_Channel, param1: u16) -> i32
OnOutgoingMessageSent_func_ptr_anon_5 :: #type proc "c" (param0: ^NBN_Channel, param1: ^NBN_Message) -> i32
NBN_UnreliableOrderedChannel :: struct {
    base: NBN_Channel,
    last_received_message_id: u16,
    next_outgoing_message_slot: u32,
}
NBN_ReliableOrderedChannel :: struct {
    base: NBN_Channel,
    oldest_unacked_message_id: u16,
    most_recent_message_id: u16,
    ack_buffer: [1024]b8,
}
NBN_MessageEntry :: struct {
    id: u16,
    channel_id: u8,
}
NBN_PacketEntry :: struct {
    acked: b8,
    flagged_as_lost: b8,
    messages_count: u32,
    send_time: f64,
    messages: [255]NBN_MessageEntry,
}
NBN_ConnectionStats :: struct {
    ping: f64,
    total_lost_packets: u32,
    packet_loss: f32,
    upload_bandwidth: f32,
    download_bandwidth: f32,
}
NBN_ConnectionKeySet :: struct {
    pub_key: [64]u8,
    prv_key: [32]u8,
    shared_key: [64]u8,
}
NBN_ConnectionListNode :: struct {
    conn: ^NBN_Connection,
    next: ^NBN_ConnectionListNode,
    prev: ^NBN_ConnectionListNode,
}
NBN_GameClient :: struct {
    endpoint: NBN_Endpoint,
    server_connection: ^NBN_Connection,
    is_connected: b8,
    server_data: [1024]u8,
    server_data_len: u32,
    last_event: NBN_Event,
    closed_code: i32,
}
NBN_GameServerStats :: struct {
    upload_bandwidth: f32,
    download_bandwidth: f32,
}
NBN_GameServer :: struct {
    endpoint: NBN_Endpoint,
    clients: [^]NBN_ConnectionVector,
    clients_table: ^NBN_ConnectionTable,
    closed_clients_head: ^NBN_ConnectionListNode,
    stats: NBN_GameServerStats,
    last_event: NBN_Event,
    last_connection_data: [512]u8,
    last_connection_data_len: u32,
}
NBN_DriverEvent :: enum i32 {NBN_DRIVER_CLI_PACKET_RECEIVED = 0, NBN_DRIVER_SERV_CLIENT_CONNECTED = 1, NBN_DRIVER_SERV_CLIENT_PACKET_RECEIVED = 2, }

foreign import nbnet_runic "system:nbnet.a"

@(default_calling_convention = "c")
foreign nbnet_runic {
    @(link_name = "nbn_mem_manager")
    nbn_mem_manager: NBN_MemoryManager

    @(link_name = "NBN_BitReader_Init")
    BitReader_Init :: proc(param0: ^NBN_BitReader, param1: ^u8, param2: u32) ---

    @(link_name = "NBN_BitReader_Read")
    BitReader_Read :: proc(param0: ^NBN_BitReader, param1: ^Word, param2: u32) -> i32 ---

    @(link_name = "NBN_BitWriter_Init")
    BitWriter_Init :: proc(param0: ^NBN_BitWriter, param1: ^u8, param2: u32) ---

    @(link_name = "NBN_BitWriter_Write")
    BitWriter_Write :: proc(param0: ^NBN_BitWriter, param1: Word, param2: u32) -> i32 ---

    @(link_name = "NBN_BitWriter_Flush")
    BitWriter_Flush :: proc(param0: ^NBN_BitWriter) -> i32 ---

    @(link_name = "NBN_ReadStream_Init")
    ReadStream_Init :: proc(param0: ^NBN_ReadStream, param1: ^u8, param2: u32) ---

    @(link_name = "NBN_ReadStream_SerializeUint")
    ReadStream_SerializeUint :: proc(param0: ^NBN_ReadStream, param1: ^u32, param2: u32, param3: u32) -> i32 ---

    @(link_name = "NBN_ReadStream_SerializeUint64")
    ReadStream_SerializeUint64 :: proc(read_stream: ^NBN_ReadStream, value: ^u64) -> i32 ---

    @(link_name = "NBN_ReadStream_SerializeInt")
    ReadStream_SerializeInt :: proc(param0: ^NBN_ReadStream, param1: ^i32, param2: i32, param3: i32) -> i32 ---

    @(link_name = "NBN_ReadStream_SerializeFloat")
    ReadStream_SerializeFloat :: proc(param0: ^NBN_ReadStream, param1: ^f32, param2: f32, param3: f32, param4: i32) -> i32 ---

    @(link_name = "NBN_ReadStream_SerializeBool")
    ReadStream_SerializeBool :: proc(param0: ^NBN_ReadStream, param1: ^b8) -> i32 ---

    @(link_name = "NBN_ReadStream_SerializePadding")
    ReadStream_SerializePadding :: proc(param0: ^NBN_ReadStream) -> i32 ---

    @(link_name = "NBN_ReadStream_SerializeBytes")
    ReadStream_SerializeBytes :: proc(param0: ^NBN_ReadStream, param1: ^u8, param2: u32) -> i32 ---

    @(link_name = "NBN_WriteStream_Init")
    WriteStream_Init :: proc(param0: ^NBN_WriteStream, param1: ^u8, param2: u32) ---

    @(link_name = "NBN_WriteStream_SerializeUint")
    WriteStream_SerializeUint :: proc(param0: ^NBN_WriteStream, param1: ^u32, param2: u32, param3: u32) -> i32 ---

    @(link_name = "NBN_WriteStream_SerializeUint64")
    WriteStream_SerializeUint64 :: proc(write_stream: ^NBN_WriteStream, value: ^u64) -> i32 ---

    @(link_name = "NBN_WriteStream_SerializeInt")
    WriteStream_SerializeInt :: proc(param0: ^NBN_WriteStream, param1: ^i32, param2: i32, param3: i32) -> i32 ---

    @(link_name = "NBN_WriteStream_SerializeFloat")
    WriteStream_SerializeFloat :: proc(param0: ^NBN_WriteStream, param1: ^f32, param2: f32, param3: f32, param4: i32) -> i32 ---

    @(link_name = "NBN_WriteStream_SerializeBool")
    WriteStream_SerializeBool :: proc(param0: ^NBN_WriteStream, param1: ^b8) -> i32 ---

    @(link_name = "NBN_WriteStream_SerializePadding")
    WriteStream_SerializePadding :: proc(param0: ^NBN_WriteStream) -> i32 ---

    @(link_name = "NBN_WriteStream_SerializeBytes")
    WriteStream_SerializeBytes :: proc(param0: ^NBN_WriteStream, param1: ^u8, param2: u32) -> i32 ---

    @(link_name = "NBN_WriteStream_Flush")
    WriteStream_Flush :: proc(param0: ^NBN_WriteStream) -> i32 ---

    @(link_name = "NBN_MeasureStream_Init")
    MeasureStream_Init :: proc(param0: ^NBN_MeasureStream) ---

    @(link_name = "NBN_MeasureStream_SerializeUint")
    MeasureStream_SerializeUint :: proc(param0: ^NBN_MeasureStream, param1: ^u32, param2: u32, param3: u32) -> i32 ---

    @(link_name = "NBN_MeasureStream_SerializeUint64")
    MeasureStream_SerializeUint64 :: proc(measure_stream: ^NBN_MeasureStream, value: ^u32) -> i32 ---

    @(link_name = "NBN_MeasureStream_SerializeInt")
    MeasureStream_SerializeInt :: proc(param0: ^NBN_MeasureStream, param1: ^i32, param2: i32, param3: i32) -> i32 ---

    @(link_name = "NBN_MeasureStream_SerializeFloat")
    MeasureStream_SerializeFloat :: proc(param0: ^NBN_MeasureStream, param1: ^f32, param2: f32, param3: f32, param4: i32) -> i32 ---

    @(link_name = "NBN_MeasureStream_SerializeBool")
    MeasureStream_SerializeBool :: proc(param0: ^NBN_MeasureStream, param1: ^b8) -> i32 ---

    @(link_name = "NBN_MeasureStream_SerializePadding")
    MeasureStream_SerializePadding :: proc(param0: ^NBN_MeasureStream) -> i32 ---

    @(link_name = "NBN_MeasureStream_SerializeBytes")
    MeasureStream_SerializeBytes :: proc(param0: ^NBN_MeasureStream, param1: ^u8, param2: u32) -> i32 ---

    @(link_name = "NBN_MeasureStream_Reset")
    MeasureStream_Reset :: proc(param0: ^NBN_MeasureStream) ---

    @(link_name = "NBN_Message_SerializeHeader")
    Message_SerializeHeader :: proc(param0: ^NBN_MessageHeader, param1: ^NBN_Stream) -> i32 ---

    @(link_name = "NBN_Message_Measure")
    Message_Measure :: proc(param0: ^NBN_Message, param1: ^NBN_MeasureStream, param2: NBN_MessageSerializer) -> i32 ---

    @(link_name = "NBN_Message_SerializeData")
    Message_SerializeData :: proc(param0: ^NBN_Message, param1: ^NBN_Stream, param2: NBN_MessageSerializer) -> i32 ---

    @(link_name = "NBN_Packet_InitWrite")
    Packet_InitWrite :: proc(param0: ^NBN_Packet, param1: u32, param2: u16, param3: u16, param4: u32) ---

    @(link_name = "NBN_Packet_InitRead")
    Packet_InitRead :: proc(param0: ^NBN_Packet, param1: ^NBN_Connection, param2: [1400]u8, param3: u32) -> i32 ---

    @(link_name = "NBN_Packet_ReadProtocolId")
    Packet_ReadProtocolId :: proc(param0: [1400]u8, param1: u32) -> u32 ---

    @(link_name = "NBN_Packet_WriteMessage")
    Packet_WriteMessage :: proc(param0: ^NBN_Packet, param1: ^NBN_Message, param2: NBN_MessageSerializer) -> i32 ---

    @(link_name = "NBN_Packet_Seal")
    Packet_Seal :: proc(param0: ^NBN_Packet, param1: ^NBN_Connection) -> i32 ---

    @(link_name = "NBN_Packet_Encrypt")
    Packet_Encrypt :: proc(param0: ^NBN_Packet, param1: ^NBN_Connection) ---

    @(link_name = "NBN_Packet_Decrypt")
    Packet_Decrypt :: proc(param0: ^NBN_Packet, param1: ^NBN_Connection) ---

    @(link_name = "NBN_Packet_ComputeIV")
    Packet_ComputeIV :: proc(param0: ^NBN_Packet, param1: ^NBN_Connection) ---

    @(link_name = "NBN_Packet_Authenticate")
    Packet_Authenticate :: proc(param0: ^NBN_Packet, param1: ^NBN_Connection) ---

    @(link_name = "NBN_Packet_CheckAuthentication")
    Packet_CheckAuthentication :: proc(param0: ^NBN_Packet, param1: ^NBN_Connection) -> b8 ---

    @(link_name = "NBN_Packet_ComputePoly1305Key")
    Packet_ComputePoly1305Key :: proc(param0: ^NBN_Packet, param1: ^NBN_Connection, param2: ^u8) ---

    @(link_name = "NBN_MessageChunk_Create")
    MessageChunk_Create :: proc() -> ^NBN_MessageChunk ---

    @(link_name = "NBN_MessageChunk_Destroy")
    MessageChunk_Destroy :: proc(param0: ^NBN_MessageChunk) ---

    @(link_name = "NBN_MessageChunk_Serialize")
    MessageChunk_Serialize :: proc(param0: ^NBN_MessageChunk, param1: ^NBN_Stream) -> i32 ---

    @(link_name = "NBN_ClientClosedMessage_Create")
    ClientClosedMessage_Create :: proc() -> ^NBN_ClientClosedMessage ---

    @(link_name = "NBN_ClientClosedMessage_Destroy")
    ClientClosedMessage_Destroy :: proc(param0: ^NBN_ClientClosedMessage) ---

    @(link_name = "NBN_ClientClosedMessage_Serialize")
    ClientClosedMessage_Serialize :: proc(param0: ^NBN_ClientClosedMessage, param1: ^NBN_Stream) -> i32 ---

    @(link_name = "NBN_ClientAcceptedMessage_Create")
    ClientAcceptedMessage_Create :: proc() -> ^NBN_ClientAcceptedMessage ---

    @(link_name = "NBN_ClientAcceptedMessage_Destroy")
    ClientAcceptedMessage_Destroy :: proc(param0: ^NBN_ClientAcceptedMessage) ---

    @(link_name = "NBN_ClientAcceptedMessage_Serialize")
    ClientAcceptedMessage_Serialize :: proc(param0: ^NBN_ClientAcceptedMessage, param1: ^NBN_Stream) -> i32 ---

    @(link_name = "NBN_ByteArrayMessage_Create")
    ByteArrayMessage_Create :: proc() -> ^NBN_ByteArrayMessage ---

    @(link_name = "NBN_ByteArrayMessage_Destroy")
    ByteArrayMessage_Destroy :: proc(param0: ^NBN_ByteArrayMessage) ---

    @(link_name = "NBN_ByteArrayMessage_Serialize")
    ByteArrayMessage_Serialize :: proc(param0: ^NBN_ByteArrayMessage, param1: ^NBN_Stream) -> i32 ---

    @(link_name = "NBN_PublicCryptoInfoMessage_Create")
    PublicCryptoInfoMessage_Create :: proc() -> ^NBN_PublicCryptoInfoMessage ---

    @(link_name = "NBN_PublicCryptoInfoMessage_Destroy")
    PublicCryptoInfoMessage_Destroy :: proc(param0: ^NBN_PublicCryptoInfoMessage) ---

    @(link_name = "NBN_PublicCryptoInfoMessage_Serialize")
    PublicCryptoInfoMessage_Serialize :: proc(param0: ^NBN_PublicCryptoInfoMessage, param1: ^NBN_Stream) -> i32 ---

    @(link_name = "NBN_StartEncryptMessage_Create")
    StartEncryptMessage_Create :: proc() -> rawptr ---

    @(link_name = "NBN_StartEncryptMessage_Destroy")
    StartEncryptMessage_Destroy :: proc(param0: rawptr) ---

    @(link_name = "NBN_StartEncryptMessage_Serialize")
    StartEncryptMessage_Serialize :: proc(param0: rawptr, param1: ^NBN_Stream) -> i32 ---

    @(link_name = "NBN_DisconnectionMessage_Create")
    DisconnectionMessage_Create :: proc() -> rawptr ---

    @(link_name = "NBN_DisconnectionMessage_Destroy")
    DisconnectionMessage_Destroy :: proc(param0: rawptr) ---

    @(link_name = "NBN_DisconnectionMessage_Serialize")
    DisconnectionMessage_Serialize :: proc(param0: rawptr, param1: ^NBN_Stream) -> i32 ---

    @(link_name = "NBN_ConnectionRequestMessage_Create")
    ConnectionRequestMessage_Create :: proc() -> ^NBN_ConnectionRequestMessage ---

    @(link_name = "NBN_ConnectionRequestMessage_Destroy")
    ConnectionRequestMessage_Destroy :: proc(param0: ^NBN_ConnectionRequestMessage) ---

    @(link_name = "NBN_ConnectionRequestMessage_Serialize")
    ConnectionRequestMessage_Serialize :: proc(param0: ^NBN_ConnectionRequestMessage, param1: ^NBN_Stream) -> i32 ---

    @(link_name = "NBN_RPC_Message_Create")
    RPC_Message_Create :: proc() -> rawptr ---

    @(link_name = "NBN_RPC_Message_Destroy")
    RPC_Message_Destroy :: proc(param0: ^NBN_RPC_Message) ---

    @(link_name = "NBN_RPC_Message_Serialize")
    RPC_Message_Serialize :: proc(param0: ^NBN_RPC_Message, param1: ^NBN_Stream) -> i32 ---

    @(link_name = "NBN_Channel_Destroy")
    Channel_Destroy :: proc(param0: ^NBN_Channel) ---

    @(link_name = "NBN_Channel_AddChunk")
    Channel_AddChunk :: proc(param0: ^NBN_Channel, param1: ^NBN_Message) -> b8 ---

    @(link_name = "NBN_Channel_ReconstructMessageFromChunks")
    Channel_ReconstructMessageFromChunks :: proc(param0: ^NBN_Channel, param1: ^NBN_Connection, param2: ^NBN_Message) -> i32 ---

    @(link_name = "NBN_Channel_ResizeWriteChunkBuffer")
    Channel_ResizeWriteChunkBuffer :: proc(param0: ^NBN_Channel, param1: u32) ---

    @(link_name = "NBN_Channel_ResizeReadChunkBuffer")
    Channel_ResizeReadChunkBuffer :: proc(param0: ^NBN_Channel, param1: u32) ---

    @(link_name = "NBN_Channel_UpdateMessageLastSendTime")
    Channel_UpdateMessageLastSendTime :: proc(param0: ^NBN_Channel, param1: ^NBN_Message, param2: f64) ---

    @(link_name = "NBN_UnreliableOrderedChannel_Create")
    UnreliableOrderedChannel_Create :: proc() -> ^NBN_UnreliableOrderedChannel ---

    @(link_name = "NBN_ReliableOrderedChannel_Create")
    ReliableOrderedChannel_Create :: proc() -> ^NBN_ReliableOrderedChannel ---

    @(link_name = "NBN_Connection_Create")
    Connection_Create :: proc(param0: u32, param1: u32, param2: ^NBN_Endpoint, param3: ^NBN_Driver, param4: rawptr, param5: b8) -> ^NBN_Connection ---

    @(link_name = "NBN_Connection_Destroy")
    Connection_Destroy :: proc(param0: ^NBN_Connection) ---

    @(link_name = "NBN_Connection_ProcessReceivedPacket")
    Connection_ProcessReceivedPacket :: proc(param0: ^NBN_Connection, param1: ^NBN_Packet, param2: f64) -> i32 ---

    @(link_name = "NBN_Connection_EnqueueOutgoingMessage")
    Connection_EnqueueOutgoingMessage :: proc(param0: ^NBN_Connection, param1: ^NBN_Channel, param2: ^NBN_Message) -> i32 ---

    @(link_name = "NBN_Connection_FlushSendQueue")
    Connection_FlushSendQueue :: proc(param0: ^NBN_Connection, param1: f64) -> i32 ---

    @(link_name = "NBN_Connection_InitChannel")
    Connection_InitChannel :: proc(param0: ^NBN_Connection, param1: ^NBN_Channel) -> i32 ---

    @(link_name = "NBN_Connection_CheckIfStale")
    Connection_CheckIfStale :: proc(param0: ^NBN_Connection, param1: f64) -> b8 ---

    @(link_name = "NBN_EventQueue_Create")
    EventQueue_Create :: proc() -> ^NBN_EventQueue ---

    @(link_name = "NBN_EventQueue_Destroy")
    EventQueue_Destroy :: proc(param0: ^NBN_EventQueue) ---

    @(link_name = "NBN_EventQueue_Enqueue")
    EventQueue_Enqueue :: proc(param0: ^NBN_EventQueue, param1: NBN_Event) -> b8 ---

    @(link_name = "NBN_EventQueue_Dequeue")
    EventQueue_Dequeue :: proc(param0: ^NBN_EventQueue, param1: ^NBN_Event) -> b8 ---

    @(link_name = "NBN_EventQueue_IsEmpty")
    EventQueue_IsEmpty :: proc(param0: ^NBN_EventQueue) -> b8 ---

    @(link_name = "nbn_game_client")
    nbn_game_client: NBN_GameClient

    @(link_name = "NBN_GameClient_Start")
    GameClient_Start :: proc(protocol_name: cstring, host: cstring, port: u16) -> i32 ---

    @(link_name = "NBN_GameClient_StartEx")
    GameClient_StartEx :: proc(protocol_name: cstring, host: cstring, port: u16, enable_encryption: b8, data: ^u8, length: u32) -> i32 ---

    @(link_name = "NBN_GameClient_Stop")
    GameClient_Stop :: proc() ---

    @(link_name = "NBN_GameClient_ReadServerData")
    GameClient_ReadServerData :: proc(data: ^u8) -> u32 ---

    @(link_name = "NBN_GameClient_RegisterMessage")
    GameClient_RegisterMessage :: proc(msg_type: u8, msg_builder: NBN_MessageBuilder, msg_destructor: NBN_MessageDestructor, msg_serializer: NBN_MessageSerializer) ---

    @(link_name = "NBN_GameClient_Poll")
    GameClient_Poll :: proc() -> i32 ---

    @(link_name = "NBN_GameClient_SendPackets")
    GameClient_SendPackets :: proc() -> i32 ---

    @(link_name = "NBN_GameClient_SendByteArray")
    GameClient_SendByteArray :: proc(bytes: [^]u8, length: u32, channel_id: u8) -> i32 ---

    @(link_name = "NBN_GameClient_SendMessage")
    GameClient_SendMessage :: proc(msg_type: u8, channel_id: u8, msg_data: rawptr) -> i32 ---

    @(link_name = "NBN_GameClient_SendUnreliableMessage")
    GameClient_SendUnreliableMessage :: proc(msg_type: u8, msg_data: rawptr) -> i32 ---

    @(link_name = "NBN_GameClient_SendReliableMessage")
    GameClient_SendReliableMessage :: proc(msg_type: u8, msg_data: rawptr) -> i32 ---

    @(link_name = "NBN_GameClient_SendUnreliableByteArray")
    GameClient_SendUnreliableByteArray :: proc(bytes: [^]u8, length: u32) -> i32 ---

    @(link_name = "NBN_GameClient_SendReliableByteArray")
    GameClient_SendReliableByteArray :: proc(bytes: [^]u8, length: u32) -> i32 ---

    @(link_name = "NBN_GameClient_CreateServerConnection")
    GameClient_CreateServerConnection :: proc(driver_id: i32, driver_data: rawptr, protocol_id: u32, is_encrypted: b8) -> ^NBN_Connection ---

    @(link_name = "NBN_GameClient_GetMessageInfo")
    GameClient_GetMessageInfo :: proc() -> NBN_MessageInfo ---

    @(link_name = "NBN_GameClient_GetStats")
    GameClient_GetStats :: proc() -> NBN_ConnectionStats ---

    @(link_name = "NBN_GameClient_GetServerCloseCode")
    GameClient_GetServerCloseCode :: proc() -> i32 ---

    @(link_name = "NBN_GameClient_IsConnected")
    GameClient_IsConnected :: proc() -> b8 ---

    @(link_name = "NBN_GameClient_RegisterRPC")
    GameClient_RegisterRPC :: proc(id: u32, signature: NBN_RPC_Signature, func: NBN_RPC_Func) -> i32 ---

    @(link_name = "NBN_GameClient_CallRPC")
    GameClient_CallRPC :: proc(id: u32, #c_vararg var_args: ..any) -> i32 ---

    @(link_name = "nbn_game_server")
    nbn_game_server: NBN_GameServer

    @(link_name = "NBN_GameServer_Start")
    GameServer_Start :: proc(protocol_name: cstring, port: u16) -> i32 ---

    @(link_name = "NBN_GameServer_StartEx")
    GameServer_StartEx :: proc(protocol_name: cstring, port: u16, enable_encryption: b8) -> i32 ---

    @(link_name = "NBN_GameServer_Stop")
    GameServer_Stop :: proc() ---

    @(link_name = "NBN_GameServer_RegisterMessage")
    GameServer_RegisterMessage :: proc(msg_type: u8, msg_builder: NBN_MessageBuilder, msg_destructor: NBN_MessageDestructor, msg_serializer: NBN_MessageSerializer) ---

    @(link_name = "NBN_GameServer_Poll")
    GameServer_Poll :: proc() -> i32 ---

    @(link_name = "NBN_GameServer_SendPackets")
    GameServer_SendPackets :: proc() -> i32 ---

    @(link_name = "NBN_GameServer_CreateClientConnection")
    GameServer_CreateClientConnection :: proc(param0: i32, param1: rawptr, param2: u32, param3: u32, param4: b8) -> ^NBN_Connection ---

    @(link_name = "NBN_GameServer_CloseClient")
    GameServer_CloseClient :: proc(connection_handle: NBN_ConnectionHandle) -> i32 ---

    @(link_name = "NBN_GameServer_CloseClientWithCode")
    GameServer_CloseClientWithCode :: proc(connection_handle: NBN_ConnectionHandle, code: i32) -> i32 ---

    @(link_name = "NBN_GameServer_SendByteArrayTo")
    GameServer_SendByteArrayTo :: proc(connection_handle: NBN_ConnectionHandle, bytes: [^]u8, length: u32, channel_id: u8) -> i32 ---

    @(link_name = "NBN_GameServer_SendMessageTo")
    GameServer_SendMessageTo :: proc(connection_handle: NBN_ConnectionHandle, msg_type: u8, channel_id: u8, msg_data: rawptr) -> i32 ---

    @(link_name = "NBN_GameServer_SendUnreliableMessageTo")
    GameServer_SendUnreliableMessageTo :: proc(connection_handle: NBN_ConnectionHandle, msg_type: u8, msg_data: rawptr) -> i32 ---

    @(link_name = "NBN_GameServer_SendReliableMessageTo")
    GameServer_SendReliableMessageTo :: proc(connection_handle: NBN_ConnectionHandle, msg_type: u8, msg_data: rawptr) -> i32 ---

    @(link_name = "NBN_GameServer_SendUnreliableByteArrayTo")
    GameServer_SendUnreliableByteArrayTo :: proc(connection_handle: NBN_ConnectionHandle, bytes: [^]u8, length: u32) -> i32 ---

    @(link_name = "NBN_GameServer_SendReliableByteArrayTo")
    GameServer_SendReliableByteArrayTo :: proc(connection_handle: NBN_ConnectionHandle, bytes: [^]u8, length: u32) -> i32 ---

    @(link_name = "NBN_GameServer_AcceptIncomingConnectionWithData")
    GameServer_AcceptIncomingConnectionWithData :: proc(data: ^u8, length: u32) -> i32 ---

    @(link_name = "NBN_GameServer_AcceptIncomingConnection")
    GameServer_AcceptIncomingConnection :: proc() -> i32 ---

    @(link_name = "NBN_GameServer_RejectIncomingConnectionWithCode")
    GameServer_RejectIncomingConnectionWithCode :: proc(code: i32) -> i32 ---

    @(link_name = "NBN_GameServer_RejectIncomingConnection")
    GameServer_RejectIncomingConnection :: proc() -> i32 ---

    @(link_name = "NBN_GameServer_GetIncomingConnection")
    GameServer_GetIncomingConnection :: proc() -> NBN_ConnectionHandle ---

    @(link_name = "NBN_GameServer_ReadIncomingConnectionData")
    GameServer_ReadIncomingConnectionData :: proc(data: ^u8) -> u32 ---

    @(link_name = "NBN_GameServer_GetDisconnectedClient")
    GameServer_GetDisconnectedClient :: proc() -> NBN_ConnectionHandle ---

    @(link_name = "NBN_GameServer_GetMessageInfo")
    GameServer_GetMessageInfo :: proc() -> NBN_MessageInfo ---

    @(link_name = "NBN_GameServer_GetStats")
    GameServer_GetStats :: proc() -> NBN_GameServerStats ---

    @(link_name = "NBN_GameServer_RegisterRPC")
    GameServer_RegisterRPC :: proc(id: u32, signature: NBN_RPC_Signature, func: NBN_RPC_Func) -> i32 ---

    @(link_name = "NBN_GameServer_CallRPC")
    GameServer_CallRPC :: proc(id: u32, connection_handle: NBN_ConnectionHandle, #c_vararg var_args: ..any) -> i32 ---

    @(link_name = "NBN_Driver_Register")
    Driver_Register :: proc(id: i32, name: cstring, implementation: NBN_DriverImplementation) ---

    @(link_name = "NBN_Driver_RaiseEvent")
    Driver_RaiseEvent :: proc(ev: NBN_DriverEvent, data: rawptr) -> i32 ---

}

