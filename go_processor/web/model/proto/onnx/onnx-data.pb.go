


package onnx

import (
	protoreflect "google.golang.org/protobuf/reflect/protoreflect"
	protoimpl "google.golang.org/protobuf/runtime/protoimpl"
	reflect "reflect"
	sync "sync"
	unsafe "unsafe"
)

const (
	_ = protoimpl.EnforceVersion(20 - protoimpl.MinVersion)
	_ = protoimpl.EnforceVersion(protoimpl.MaxVersion - 20)
)

type SequenceProto_DataType int32

const (
	SequenceProto_UNDEFINED     SequenceProto_DataType = 0
	SequenceProto_TENSOR        SequenceProto_DataType = 1
	SequenceProto_SPARSE_TENSOR SequenceProto_DataType = 2
	SequenceProto_SEQUENCE      SequenceProto_DataType = 3
	SequenceProto_MAP           SequenceProto_DataType = 4
	SequenceProto_OPTIONAL      SequenceProto_DataType = 5
)

var (
	SequenceProto_DataType_name = map[int32]string{
		0: "UNDEFINED",
		1: "TENSOR",
		2: "SPARSE_TENSOR",
		3: "SEQUENCE",
		4: "MAP",
		5: "OPTIONAL",
	}
	SequenceProto_DataType_value = map[string]int32{
		"UNDEFINED":     0,
		"TENSOR":        1,
		"SPARSE_TENSOR": 2,
		"SEQUENCE":      3,
		"MAP":           4,
		"OPTIONAL":      5,
	}
)

func (x SequenceProto_DataType) Enum() *SequenceProto_DataType {
	p := new(SequenceProto_DataType)
	*p = x
	return p
}

func (x SequenceProto_DataType) String() string {
	return protoimpl.X.EnumStringOf(x.Descriptor(), protoreflect.EnumNumber(x))
}

func (SequenceProto_DataType) Descriptor() protoreflect.EnumDescriptor {
	return file_onnx_data_proto_enumTypes[0].Descriptor()
}

func (SequenceProto_DataType) Type() protoreflect.EnumType {
	return &file_onnx_data_proto_enumTypes[0]
}

func (x SequenceProto_DataType) Number() protoreflect.EnumNumber {
	return protoreflect.EnumNumber(x)
}

func (x *SequenceProto_DataType) UnmarshalJSON(b []byte) error {
	num, err := protoimpl.X.UnmarshalJSONEnum(x.Descriptor(), b)
	if err != nil {
		return err
	}
	*x = SequenceProto_DataType(num)
	return nil
}

func (SequenceProto_DataType) EnumDescriptor() ([]byte, []int) {
	return file_onnx_data_proto_rawDescGZIP(), []int{0, 0}
}

type OptionalProto_DataType int32

const (
	OptionalProto_UNDEFINED     OptionalProto_DataType = 0
	OptionalProto_TENSOR        OptionalProto_DataType = 1
	OptionalProto_SPARSE_TENSOR OptionalProto_DataType = 2
	OptionalProto_SEQUENCE      OptionalProto_DataType = 3
	OptionalProto_MAP           OptionalProto_DataType = 4
	OptionalProto_OPTIONAL      OptionalProto_DataType = 5
)

var (
	OptionalProto_DataType_name = map[int32]string{
		0: "UNDEFINED",
		1: "TENSOR",
		2: "SPARSE_TENSOR",
		3: "SEQUENCE",
		4: "MAP",
		5: "OPTIONAL",
	}
	OptionalProto_DataType_value = map[string]int32{
		"UNDEFINED":     0,
		"TENSOR":        1,
		"SPARSE_TENSOR": 2,
		"SEQUENCE":      3,
		"MAP":           4,
		"OPTIONAL":      5,
	}
)

func (x OptionalProto_DataType) Enum() *OptionalProto_DataType {
	p := new(OptionalProto_DataType)
	*p = x
	return p
}

func (x OptionalProto_DataType) String() string {
	return protoimpl.X.EnumStringOf(x.Descriptor(), protoreflect.EnumNumber(x))
}

func (OptionalProto_DataType) Descriptor() protoreflect.EnumDescriptor {
	return file_onnx_data_proto_enumTypes[1].Descriptor()
}

func (OptionalProto_DataType) Type() protoreflect.EnumType {
	return &file_onnx_data_proto_enumTypes[1]
}

func (x OptionalProto_DataType) Number() protoreflect.EnumNumber {
	return protoreflect.EnumNumber(x)
}

func (x *OptionalProto_DataType) UnmarshalJSON(b []byte) error {
	num, err := protoimpl.X.UnmarshalJSONEnum(x.Descriptor(), b)
	if err != nil {
		return err
	}
	*x = OptionalProto_DataType(num)
	return nil
}

func (OptionalProto_DataType) EnumDescriptor() ([]byte, []int) {
	return file_onnx_data_proto_rawDescGZIP(), []int{2, 0}
}

type SequenceProto struct {
	state          protoimpl.MessageState `protogen:"open.v1"`
	Name           *string                `protobuf:"bytes,1,opt,name=name" json:"name,omitempty"`
	ElemType       *int32                 `protobuf:"varint,2,opt,name=elem_type,json=elemType" json:"elem_type,omitempty"`
	MapValues      []*MapProto            `protobuf:"bytes,3,rep,name=map_values,json=mapValues" json:"map_values,omitempty"`
	OptionalValues []*OptionalProto       `protobuf:"bytes,4,rep,name=optional_values,json=optionalValues" json:"optional_values,omitempty"`
	unknownFields  protoimpl.UnknownFields
	sizeCache      protoimpl.SizeCache
}

func (x *SequenceProto) Reset() {
	*x = SequenceProto{}
	mi := &file_onnx_data_proto_msgTypes[0]
	ms := protoimpl.X.MessageStateOf(protoimpl.Pointer(x))
	ms.StoreMessageInfo(mi)
}

func (x *SequenceProto) String() string {
	return protoimpl.X.MessageStringOf(x)
}

func (*SequenceProto) ProtoMessage() {}

func (x *SequenceProto) ProtoReflect() protoreflect.Message {
	mi := &file_onnx_data_proto_msgTypes[0]
	if x != nil {
		ms := protoimpl.X.MessageStateOf(protoimpl.Pointer(x))
		if ms.LoadMessageInfo() == nil {
			ms.StoreMessageInfo(mi)
		}
		return ms
	}
	return mi.MessageOf(x)
}

func (*SequenceProto) Descriptor() ([]byte, []int) {
	return file_onnx_data_proto_rawDescGZIP(), []int{0}
}

func (x *SequenceProto) GetName() string {
	if x != nil && x.Name != nil {
		return *x.Name
	}
	return ""
}

func (x *SequenceProto) GetElemType() int32 {
	if x != nil && x.ElemType != nil {
		return *x.ElemType
	}
	return 0
}

func (x *SequenceProto) GetMapValues() []*MapProto {
	if x != nil {
		return x.MapValues
	}
	return nil
}

func (x *SequenceProto) GetOptionalValues() []*OptionalProto {
	if x != nil {
		return x.OptionalValues
	}
	return nil
}

type MapProto struct {
	state         protoimpl.MessageState `protogen:"open.v1"`
	Name          *string                `protobuf:"bytes,1,opt,name=name" json:"name,omitempty"`
	KeyType       *int32                 `protobuf:"varint,2,opt,name=key_type,json=keyType" json:"key_type,omitempty"`
	Keys          []int64                `protobuf:"varint,3,rep,name=keys" json:"keys,omitempty"`
	StringKeys    [][]byte               `protobuf:"bytes,4,rep,name=string_keys,json=stringKeys" json:"string_keys,omitempty"`
	Values        *SequenceProto         `protobuf:"bytes,5,opt,name=values" json:"values,omitempty"`
	unknownFields protoimpl.UnknownFields
	sizeCache     protoimpl.SizeCache
}

func (x *MapProto) Reset() {
	*x = MapProto{}
	mi := &file_onnx_data_proto_msgTypes[1]
	ms := protoimpl.X.MessageStateOf(protoimpl.Pointer(x))
	ms.StoreMessageInfo(mi)
}

func (x *MapProto) String() string {
	return protoimpl.X.MessageStringOf(x)
}

func (*MapProto) ProtoMessage() {}

func (x *MapProto) ProtoReflect() protoreflect.Message {
	mi := &file_onnx_data_proto_msgTypes[1]
	if x != nil {
		ms := protoimpl.X.MessageStateOf(protoimpl.Pointer(x))
		if ms.LoadMessageInfo() == nil {
			ms.StoreMessageInfo(mi)
		}
		return ms
	}
	return mi.MessageOf(x)
}

func (*MapProto) Descriptor() ([]byte, []int) {
	return file_onnx_data_proto_rawDescGZIP(), []int{1}
}

func (x *MapProto) GetName() string {
	if x != nil && x.Name != nil {
		return *x.Name
	}
	return ""
}

func (x *MapProto) GetKeyType() int32 {
	if x != nil && x.KeyType != nil {
		return *x.KeyType
	}
	return 0
}

func (x *MapProto) GetKeys() []int64 {
	if x != nil {
		return x.Keys
	}
	return nil
}

func (x *MapProto) GetStringKeys() [][]byte {
	if x != nil {
		return x.StringKeys
	}
	return nil
}

func (x *MapProto) GetValues() *SequenceProto {
	if x != nil {
		return x.Values
	}
	return nil
}

type OptionalProto struct {
	state         protoimpl.MessageState `protogen:"open.v1"`
	Name          *string                `protobuf:"bytes,1,opt,name=name" json:"name,omitempty"`
	ElemType      *int32                 `protobuf:"varint,2,opt,name=elem_type,json=elemType" json:"elem_type,omitempty"`
	SequenceValue *SequenceProto         `protobuf:"bytes,3,opt,name=sequence_value,json=sequenceValue" json:"sequence_value,omitempty"`
	MapValue      *MapProto              `protobuf:"bytes,4,opt,name=map_value,json=mapValue" json:"map_value,omitempty"`
	OptionalValue *OptionalProto         `protobuf:"bytes,5,opt,name=optional_value,json=optionalValue" json:"optional_value,omitempty"`
	unknownFields protoimpl.UnknownFields
	sizeCache     protoimpl.SizeCache
}

func (x *OptionalProto) Reset() {
	*x = OptionalProto{}
	mi := &file_onnx_data_proto_msgTypes[2]
	ms := protoimpl.X.MessageStateOf(protoimpl.Pointer(x))
	ms.StoreMessageInfo(mi)
}

func (x *OptionalProto) String() string {
	return protoimpl.X.MessageStringOf(x)
}

func (*OptionalProto) ProtoMessage() {}

func (x *OptionalProto) ProtoReflect() protoreflect.Message {
	mi := &file_onnx_data_proto_msgTypes[2]
	if x != nil {
		ms := protoimpl.X.MessageStateOf(protoimpl.Pointer(x))
		if ms.LoadMessageInfo() == nil {
			ms.StoreMessageInfo(mi)
		}
		return ms
	}
	return mi.MessageOf(x)
}

func (*OptionalProto) Descriptor() ([]byte, []int) {
	return file_onnx_data_proto_rawDescGZIP(), []int{2}
}

func (x *OptionalProto) GetName() string {
	if x != nil && x.Name != nil {
		return *x.Name
	}
	return ""
}

func (x *OptionalProto) GetElemType() int32 {
	if x != nil && x.ElemType != nil {
		return *x.ElemType
	}
	return 0
}

func (x *OptionalProto) GetSequenceValue() *SequenceProto {
	if x != nil {
		return x.SequenceValue
	}
	return nil
}

func (x *OptionalProto) GetMapValue() *MapProto {
	if x != nil {
		return x.MapValue
	}
	return nil
}

func (x *OptionalProto) GetOptionalValue() *OptionalProto {
	if x != nil {
		return x.OptionalValue
	}
	return nil
}

var File_onnx_data_proto protoreflect.FileDescriptor

const file_onnx_data_proto_rawDesc = "" +
	"\n" +
	"\x0fonnx-data.proto\x12\x04onnx\"\x8c\x02\n" +
	"\rSequenceProto\x12\x12\n" +
	"\x04name\x18\x01 \x01(\tR\x04name\x12\x1b\n" +
	"\telem_type\x18\x02 \x01(\x05R\belemType\x12-\n" +
	"\n" +
	"map_values\x18\x03 \x03(\v2\x0e.onnx.MapProtoR\tmapValues\x12<\n" +
	"\x0foptional_values\x18\x04 \x03(\v2\x13.onnx.OptionalProtoR\x0eoptionalValues\"]\n" +
	"\bDataType\x12\r\n" +
	"\tUNDEFINED\x10\x00\x12\n" +
	"\n" +
	"\x06TENSOR\x10\x01\x12\x11\n" +
	"\rSPARSE_TENSOR\x10\x02\x12\f\n" +
	"\bSEQUENCE\x10\x03\x12\a\n" +
	"\x03MAP\x10\x04\x12\f\n" +
	"\bOPTIONAL\x10\x05\"\x9b\x01\n" +
	"\bMapProto\x12\x12\n" +
	"\x04name\x18\x01 \x01(\tR\x04name\x12\x19\n" +
	"\bkey_type\x18\x02 \x01(\x05R\akeyType\x12\x12\n" +
	"\x04keys\x18\x03 \x03(\x03R\x04keys\x12\x1f\n" +
	"\vstring_keys\x18\x04 \x03(\fR\n" +
	"stringKeys\x12+\n" +
	"\x06values\x18\x05 \x01(\v2\x13.onnx.SequenceProtoR\x06values\"\xc4\x02\n" +
	"\rOptionalProto\x12\x12\n" +
	"\x04name\x18\x01 \x01(\tR\x04name\x12\x1b\n" +
	"\telem_type\x18\x02 \x01(\x05R\belemType\x12:\n" +
	"\x0esequence_value\x18\x03 \x01(\v2\x13.onnx.SequenceProtoR\rsequenceValue\x12+\n" +
	"\tmap_value\x18\x04 \x01(\v2\x0e.onnx.MapProtoR\bmapValue\x12:\n" +
	"\x0eoptional_value\x18\x05 \x01(\v2\x13.onnx.OptionalProtoR\roptionalValue\"]\n" +
	"\bDataType\x12\r\n" +
	"\tUNDEFINED\x10\x00\x12\n" +
	"\n" +
	"\x06TENSOR\x10\x01\x12\x11\n" +
	"\rSPARSE_TENSOR\x10\x02\x12\f\n" +
	"\bSEQUENCE\x10\x03\x12\a\n" +
	"\x03MAP\x10\x04\x12\f\n" +
	"\bOPTIONAL\x10\x05B\vH\x03Z\a./;onnx"

var (
	file_onnx_data_proto_rawDescOnce sync.Once
	file_onnx_data_proto_rawDescData []byte
)

func file_onnx_data_proto_rawDescGZIP() []byte {
	file_onnx_data_proto_rawDescOnce.Do(func() {
		file_onnx_data_proto_rawDescData = protoimpl.X.CompressGZIP(unsafe.Slice(unsafe.StringData(file_onnx_data_proto_rawDesc), len(file_onnx_data_proto_rawDesc)))
	})
	return file_onnx_data_proto_rawDescData
}

var file_onnx_data_proto_enumTypes = make([]protoimpl.EnumInfo, 2)
var file_onnx_data_proto_msgTypes = make([]protoimpl.MessageInfo, 3)
var file_onnx_data_proto_goTypes = []any{
	(SequenceProto_DataType)(0), // 0: onnx.SequenceProto.DataType
	(OptionalProto_DataType)(0), // 1: onnx.OptionalProto.DataType
	(*SequenceProto)(nil),       // 2: onnx.SequenceProto
	(*MapProto)(nil),            // 3: onnx.MapProto
	(*OptionalProto)(nil),       // 4: onnx.OptionalProto
}
var file_onnx_data_proto_depIdxs = []int32{
	3, // 0: onnx.SequenceProto.map_values:type_name -> onnx.MapProto
	4, // 1: onnx.SequenceProto.optional_values:type_name -> onnx.OptionalProto
	2, // 2: onnx.MapProto.values:type_name -> onnx.SequenceProto
	2, // 3: onnx.OptionalProto.sequence_value:type_name -> onnx.SequenceProto
	3, // 4: onnx.OptionalProto.map_value:type_name -> onnx.MapProto
	4, // 5: onnx.OptionalProto.optional_value:type_name -> onnx.OptionalProto
	6, // [6:6] is the sub-list for method output_type
	6, // [6:6] is the sub-list for method input_type
	6, // [6:6] is the sub-list for extension type_name
	6, // [6:6] is the sub-list for extension extendee
	0, // [0:6] is the sub-list for field type_name
}

func init() { file_onnx_data_proto_init() }
func file_onnx_data_proto_init() {
	if File_onnx_data_proto != nil {
		return
	}
	type x struct{}
	out := protoimpl.TypeBuilder{
		File: protoimpl.DescBuilder{
			GoPackagePath: reflect.TypeOf(x{}).PkgPath(),
			RawDescriptor: unsafe.Slice(unsafe.StringData(file_onnx_data_proto_rawDesc), len(file_onnx_data_proto_rawDesc)),
			NumEnums:      2,
			NumMessages:   3,
			NumExtensions: 0,
			NumServices:   0,
		},
		GoTypes:           file_onnx_data_proto_goTypes,
		DependencyIndexes: file_onnx_data_proto_depIdxs,
		EnumInfos:         file_onnx_data_proto_enumTypes,
		MessageInfos:      file_onnx_data_proto_msgTypes,
	}.Build()
	File_onnx_data_proto = out.File
	file_onnx_data_proto_goTypes = nil
	file_onnx_data_proto_depIdxs = nil
}
