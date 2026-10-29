


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

type Version int32

const (
	Version_IR_VERSION_2017_10_10 Version = 1
	Version_IR_VERSION_2017_10_30 Version = 2
	Version_IR_VERSION_2017_11_3  Version = 3
	Version_IR_VERSION_2019_1_22  Version = 4
	Version_IR_VERSION_2019_3_18  Version = 5
	Version_IR_VERSION_2019_9_19  Version = 6
	Version_IR_VERSION_2020_5_8   Version = 7
	Version_IR_VERSION_2021_7_30  Version = 8
	Version_IR_VERSION_2023_5_5   Version = 9
	Version_IR_VERSION_2024_3_25  Version = 10
	Version_IR_VERSION_2025_05_12 Version = 11
	Version_IR_VERSION_2025_08_26 Version = 12
	Version_IR_VERSION            Version = 13
)

var (
	Version_name = map[int32]string{
		1:  "IR_VERSION_2017_10_10",
		2:  "IR_VERSION_2017_10_30",
		3:  "IR_VERSION_2017_11_3",
		4:  "IR_VERSION_2019_1_22",
		5:  "IR_VERSION_2019_3_18",
		6:  "IR_VERSION_2019_9_19",
		7:  "IR_VERSION_2020_5_8",
		8:  "IR_VERSION_2021_7_30",
		9:  "IR_VERSION_2023_5_5",
		10: "IR_VERSION_2024_3_25",
		11: "IR_VERSION_2025_05_12",
		12: "IR_VERSION_2025_08_26",
		13: "IR_VERSION",
	}
	Version_value = map[string]int32{
		"IR_VERSION_2017_10_10": 1,
		"IR_VERSION_2017_10_30": 2,
		"IR_VERSION_2017_11_3":  3,
		"IR_VERSION_2019_1_22":  4,
		"IR_VERSION_2019_3_18":  5,
		"IR_VERSION_2019_9_19":  6,
		"IR_VERSION_2020_5_8":   7,
		"IR_VERSION_2021_7_30":  8,
		"IR_VERSION_2023_5_5":   9,
		"IR_VERSION_2024_3_25":  10,
		"IR_VERSION_2025_05_12": 11,
		"IR_VERSION_2025_08_26": 12,
		"IR_VERSION":            13,
	}
)

func (x Version) Enum() *Version {
	p := new(Version)
	*p = x
	return p
}

func (x Version) String() string {
	return protoimpl.X.EnumStringOf(x.Descriptor(), protoreflect.EnumNumber(x))
}

func (Version) Descriptor() protoreflect.EnumDescriptor {
	return file_onnx_proto_enumTypes[0].Descriptor()
}

func (Version) Type() protoreflect.EnumType {
	return &file_onnx_proto_enumTypes[0]
}

func (x Version) Number() protoreflect.EnumNumber {
	return protoreflect.EnumNumber(x)
}

func (x *Version) UnmarshalJSON(b []byte) error {
	num, err := protoimpl.X.UnmarshalJSONEnum(x.Descriptor(), b)
	if err != nil {
		return err
	}
	*x = Version(num)
	return nil
}

func (Version) EnumDescriptor() ([]byte, []int) {
	return file_onnx_proto_rawDescGZIP(), []int{0}
}

type OperatorStatus int32

const (
	OperatorStatus_EXPERIMENTAL OperatorStatus = 0
	OperatorStatus_STABLE       OperatorStatus = 1
)

var (
	OperatorStatus_name = map[int32]string{
		0: "EXPERIMENTAL",
		1: "STABLE",
	}
	OperatorStatus_value = map[string]int32{
		"EXPERIMENTAL": 0,
		"STABLE":       1,
	}
)

func (x OperatorStatus) Enum() *OperatorStatus {
	p := new(OperatorStatus)
	*p = x
	return p
}

func (x OperatorStatus) String() string {
	return protoimpl.X.EnumStringOf(x.Descriptor(), protoreflect.EnumNumber(x))
}

func (OperatorStatus) Descriptor() protoreflect.EnumDescriptor {
	return file_onnx_proto_enumTypes[1].Descriptor()
}

func (OperatorStatus) Type() protoreflect.EnumType {
	return &file_onnx_proto_enumTypes[1]
}

func (x OperatorStatus) Number() protoreflect.EnumNumber {
	return protoreflect.EnumNumber(x)
}

func (x *OperatorStatus) UnmarshalJSON(b []byte) error {
	num, err := protoimpl.X.UnmarshalJSONEnum(x.Descriptor(), b)
	if err != nil {
		return err
	}
	*x = OperatorStatus(num)
	return nil
}

func (OperatorStatus) EnumDescriptor() ([]byte, []int) {
	return file_onnx_proto_rawDescGZIP(), []int{1}
}

type AttributeProto_AttributeType int32

const (
	AttributeProto_UNDEFINED      AttributeProto_AttributeType = 0
	AttributeProto_FLOAT          AttributeProto_AttributeType = 1
	AttributeProto_INT            AttributeProto_AttributeType = 2
	AttributeProto_STRING         AttributeProto_AttributeType = 3
	AttributeProto_TENSOR         AttributeProto_AttributeType = 4
	AttributeProto_GRAPH          AttributeProto_AttributeType = 5
	AttributeProto_SPARSE_TENSOR  AttributeProto_AttributeType = 11
	AttributeProto_TYPE_PROTO     AttributeProto_AttributeType = 13
	AttributeProto_FLOATS         AttributeProto_AttributeType = 6
	AttributeProto_INTS           AttributeProto_AttributeType = 7
	AttributeProto_STRINGS        AttributeProto_AttributeType = 8
	AttributeProto_TENSORS        AttributeProto_AttributeType = 9
	AttributeProto_GRAPHS         AttributeProto_AttributeType = 10
	AttributeProto_SPARSE_TENSORS AttributeProto_AttributeType = 12
	AttributeProto_TYPE_PROTOS    AttributeProto_AttributeType = 14
)

var (
	AttributeProto_AttributeType_name = map[int32]string{
		0:  "UNDEFINED",
		1:  "FLOAT",
		2:  "INT",
		3:  "STRING",
		4:  "TENSOR",
		5:  "GRAPH",
		11: "SPARSE_TENSOR",
		13: "TYPE_PROTO",
		6:  "FLOATS",
		7:  "INTS",
		8:  "STRINGS",
		9:  "TENSORS",
		10: "GRAPHS",
		12: "SPARSE_TENSORS",
		14: "TYPE_PROTOS",
	}
	AttributeProto_AttributeType_value = map[string]int32{
		"UNDEFINED":      0,
		"FLOAT":          1,
		"INT":            2,
		"STRING":         3,
		"TENSOR":         4,
		"GRAPH":          5,
		"SPARSE_TENSOR":  11,
		"TYPE_PROTO":     13,
		"FLOATS":         6,
		"INTS":           7,
		"STRINGS":        8,
		"TENSORS":        9,
		"GRAPHS":         10,
		"SPARSE_TENSORS": 12,
		"TYPE_PROTOS":    14,
	}
)

func (x AttributeProto_AttributeType) Enum() *AttributeProto_AttributeType {
	p := new(AttributeProto_AttributeType)
	*p = x
	return p
}

func (x AttributeProto_AttributeType) String() string {
	return protoimpl.X.EnumStringOf(x.Descriptor(), protoreflect.EnumNumber(x))
}

func (AttributeProto_AttributeType) Descriptor() protoreflect.EnumDescriptor {
	return file_onnx_proto_enumTypes[2].Descriptor()
}

func (AttributeProto_AttributeType) Type() protoreflect.EnumType {
	return &file_onnx_proto_enumTypes[2]
}

func (x AttributeProto_AttributeType) Number() protoreflect.EnumNumber {
	return protoreflect.EnumNumber(x)
}

func (x *AttributeProto_AttributeType) UnmarshalJSON(b []byte) error {
	num, err := protoimpl.X.UnmarshalJSONEnum(x.Descriptor(), b)
	if err != nil {
		return err
	}
	*x = AttributeProto_AttributeType(num)
	return nil
}

func (AttributeProto_AttributeType) EnumDescriptor() ([]byte, []int) {
	return file_onnx_proto_rawDescGZIP(), []int{0, 0}
}

type TensorProto_DataType int32

const (
	TensorProto_UNDEFINED      TensorProto_DataType = 0
	TensorProto_FLOAT          TensorProto_DataType = 1
	TensorProto_UINT8          TensorProto_DataType = 2
	TensorProto_INT8           TensorProto_DataType = 3
	TensorProto_UINT16         TensorProto_DataType = 4
	TensorProto_INT16          TensorProto_DataType = 5
	TensorProto_INT32          TensorProto_DataType = 6
	TensorProto_INT64          TensorProto_DataType = 7
	TensorProto_STRING         TensorProto_DataType = 8
	TensorProto_BOOL           TensorProto_DataType = 9
	TensorProto_FLOAT16        TensorProto_DataType = 10
	TensorProto_DOUBLE         TensorProto_DataType = 11
	TensorProto_UINT32         TensorProto_DataType = 12
	TensorProto_UINT64         TensorProto_DataType = 13
	TensorProto_COMPLEX64      TensorProto_DataType = 14
	TensorProto_COMPLEX128     TensorProto_DataType = 15
	TensorProto_BFLOAT16       TensorProto_DataType = 16
	TensorProto_FLOAT8E4M3FN   TensorProto_DataType = 17
	TensorProto_FLOAT8E4M3FNUZ TensorProto_DataType = 18
	TensorProto_FLOAT8E5M2     TensorProto_DataType = 19
	TensorProto_FLOAT8E5M2FNUZ TensorProto_DataType = 20
	TensorProto_UINT4          TensorProto_DataType = 21
	TensorProto_INT4           TensorProto_DataType = 22
	TensorProto_FLOAT4E2M1     TensorProto_DataType = 23
	TensorProto_FLOAT8E8M0     TensorProto_DataType = 24
	TensorProto_UINT2          TensorProto_DataType = 25
	TensorProto_INT2           TensorProto_DataType = 26
)

var (
	TensorProto_DataType_name = map[int32]string{
		0:  "UNDEFINED",
		1:  "FLOAT",
		2:  "UINT8",
		3:  "INT8",
		4:  "UINT16",
		5:  "INT16",
		6:  "INT32",
		7:  "INT64",
		8:  "STRING",
		9:  "BOOL",
		10: "FLOAT16",
		11: "DOUBLE",
		12: "UINT32",
		13: "UINT64",
		14: "COMPLEX64",
		15: "COMPLEX128",
		16: "BFLOAT16",
		17: "FLOAT8E4M3FN",
		18: "FLOAT8E4M3FNUZ",
		19: "FLOAT8E5M2",
		20: "FLOAT8E5M2FNUZ",
		21: "UINT4",
		22: "INT4",
		23: "FLOAT4E2M1",
		24: "FLOAT8E8M0",
		25: "UINT2",
		26: "INT2",
	}
	TensorProto_DataType_value = map[string]int32{
		"UNDEFINED":      0,
		"FLOAT":          1,
		"UINT8":          2,
		"INT8":           3,
		"UINT16":         4,
		"INT16":          5,
		"INT32":          6,
		"INT64":          7,
		"STRING":         8,
		"BOOL":           9,
		"FLOAT16":        10,
		"DOUBLE":         11,
		"UINT32":         12,
		"UINT64":         13,
		"COMPLEX64":      14,
		"COMPLEX128":     15,
		"BFLOAT16":       16,
		"FLOAT8E4M3FN":   17,
		"FLOAT8E4M3FNUZ": 18,
		"FLOAT8E5M2":     19,
		"FLOAT8E5M2FNUZ": 20,
		"UINT4":          21,
		"INT4":           22,
		"FLOAT4E2M1":     23,
		"FLOAT8E8M0":     24,
		"UINT2":          25,
		"INT2":           26,
	}
)

func (x TensorProto_DataType) Enum() *TensorProto_DataType {
	p := new(TensorProto_DataType)
	*p = x
	return p
}

func (x TensorProto_DataType) String() string {
	return protoimpl.X.EnumStringOf(x.Descriptor(), protoreflect.EnumNumber(x))
}

func (TensorProto_DataType) Descriptor() protoreflect.EnumDescriptor {
	return file_onnx_proto_enumTypes[3].Descriptor()
}

func (TensorProto_DataType) Type() protoreflect.EnumType {
	return &file_onnx_proto_enumTypes[3]
}

func (x TensorProto_DataType) Number() protoreflect.EnumNumber {
	return protoreflect.EnumNumber(x)
}

func (x *TensorProto_DataType) UnmarshalJSON(b []byte) error {
	num, err := protoimpl.X.UnmarshalJSONEnum(x.Descriptor(), b)
	if err != nil {
		return err
	}
	*x = TensorProto_DataType(num)
	return nil
}

func (TensorProto_DataType) EnumDescriptor() ([]byte, []int) {
	return file_onnx_proto_rawDescGZIP(), []int{14, 0}
}

type TensorProto_DataLocation int32

const (
	TensorProto_DEFAULT  TensorProto_DataLocation = 0
	TensorProto_EXTERNAL TensorProto_DataLocation = 1
)

var (
	TensorProto_DataLocation_name = map[int32]string{
		0: "DEFAULT",
		1: "EXTERNAL",
	}
	TensorProto_DataLocation_value = map[string]int32{
		"DEFAULT":  0,
		"EXTERNAL": 1,
	}
)

func (x TensorProto_DataLocation) Enum() *TensorProto_DataLocation {
	p := new(TensorProto_DataLocation)
	*p = x
	return p
}

func (x TensorProto_DataLocation) String() string {
	return protoimpl.X.EnumStringOf(x.Descriptor(), protoreflect.EnumNumber(x))
}

func (TensorProto_DataLocation) Descriptor() protoreflect.EnumDescriptor {
	return file_onnx_proto_enumTypes[4].Descriptor()
}

func (TensorProto_DataLocation) Type() protoreflect.EnumType {
	return &file_onnx_proto_enumTypes[4]
}

func (x TensorProto_DataLocation) Number() protoreflect.EnumNumber {
	return protoreflect.EnumNumber(x)
}

func (x *TensorProto_DataLocation) UnmarshalJSON(b []byte) error {
	num, err := protoimpl.X.UnmarshalJSONEnum(x.Descriptor(), b)
	if err != nil {
		return err
	}
	*x = TensorProto_DataLocation(num)
	return nil
}

func (TensorProto_DataLocation) EnumDescriptor() ([]byte, []int) {
	return file_onnx_proto_rawDescGZIP(), []int{14, 1}
}

type AttributeProto struct {
	state         protoimpl.MessageState        `protogen:"open.v1"`
	Name          *string                       `protobuf:"bytes,1,opt,name=name" json:"name,omitempty"`
	RefAttrName   *string                       `protobuf:"bytes,21,opt,name=ref_attr_name,json=refAttrName" json:"ref_attr_name,omitempty"`
	DocString     *string                       `protobuf:"bytes,13,opt,name=doc_string,json=docString" json:"doc_string,omitempty"`
	Type          *AttributeProto_AttributeType `protobuf:"varint,20,opt,name=type,enum=onnx.AttributeProto_AttributeType" json:"type,omitempty"`
	F             *float32                      `protobuf:"fixed32,2,opt,name=f" json:"f,omitempty"`
	I             *int64                        `protobuf:"varint,3,opt,name=i" json:"i,omitempty"`
	S             []byte                        `protobuf:"bytes,4,opt,name=s" json:"s,omitempty"`
	T             *TensorProto                  `protobuf:"bytes,5,opt,name=t" json:"t,omitempty"`
	G             *GraphProto                   `protobuf:"bytes,6,opt,name=g" json:"g,omitempty"`
	SparseTensor  *SparseTensorProto            `protobuf:"bytes,22,opt,name=sparse_tensor,json=sparseTensor" json:"sparse_tensor,omitempty"`
	Tp            *TypeProto                    `protobuf:"bytes,14,opt,name=tp" json:"tp,omitempty"`
	Floats        []float32                     `protobuf:"fixed32,7,rep,name=floats" json:"floats,omitempty"`
	Ints          []int64                       `protobuf:"varint,8,rep,name=ints" json:"ints,omitempty"`
	Strings       [][]byte                      `protobuf:"bytes,9,rep,name=strings" json:"strings,omitempty"`
	Tensors       []*TensorProto                `protobuf:"bytes,10,rep,name=tensors" json:"tensors,omitempty"`
	Graphs        []*GraphProto                 `protobuf:"bytes,11,rep,name=graphs" json:"graphs,omitempty"`
	SparseTensors []*SparseTensorProto          `protobuf:"bytes,23,rep,name=sparse_tensors,json=sparseTensors" json:"sparse_tensors,omitempty"`
	TypeProtos    []*TypeProto                  `protobuf:"bytes,15,rep,name=type_protos,json=typeProtos" json:"type_protos,omitempty"`
	unknownFields protoimpl.UnknownFields
	sizeCache     protoimpl.SizeCache
}

func (x *AttributeProto) Reset() {
	*x = AttributeProto{}
	mi := &file_onnx_proto_msgTypes[0]
	ms := protoimpl.X.MessageStateOf(protoimpl.Pointer(x))
	ms.StoreMessageInfo(mi)
}

func (x *AttributeProto) String() string {
	return protoimpl.X.MessageStringOf(x)
}

func (*AttributeProto) ProtoMessage() {}

func (x *AttributeProto) ProtoReflect() protoreflect.Message {
	mi := &file_onnx_proto_msgTypes[0]
	if x != nil {
		ms := protoimpl.X.MessageStateOf(protoimpl.Pointer(x))
		if ms.LoadMessageInfo() == nil {
			ms.StoreMessageInfo(mi)
		}
		return ms
	}
	return mi.MessageOf(x)
}

func (*AttributeProto) Descriptor() ([]byte, []int) {
	return file_onnx_proto_rawDescGZIP(), []int{0}
}

func (x *AttributeProto) GetName() string {
	if x != nil && x.Name != nil {
		return *x.Name
	}
	return ""
}

func (x *AttributeProto) GetRefAttrName() string {
	if x != nil && x.RefAttrName != nil {
		return *x.RefAttrName
	}
	return ""
}

func (x *AttributeProto) GetDocString() string {
	if x != nil && x.DocString != nil {
		return *x.DocString
	}
	return ""
}

func (x *AttributeProto) GetType() AttributeProto_AttributeType {
	if x != nil && x.Type != nil {
		return *x.Type
	}
	return AttributeProto_UNDEFINED
}

func (x *AttributeProto) GetF() float32 {
	if x != nil && x.F != nil {
		return *x.F
	}
	return 0
}

func (x *AttributeProto) GetI() int64 {
	if x != nil && x.I != nil {
		return *x.I
	}
	return 0
}

func (x *AttributeProto) GetS() []byte {
	if x != nil {
		return x.S
	}
	return nil
}

func (x *AttributeProto) GetT() *TensorProto {
	if x != nil {
		return x.T
	}
	return nil
}

func (x *AttributeProto) GetG() *GraphProto {
	if x != nil {
		return x.G
	}
	return nil
}

func (x *AttributeProto) GetSparseTensor() *SparseTensorProto {
	if x != nil {
		return x.SparseTensor
	}
	return nil
}

func (x *AttributeProto) GetTp() *TypeProto {
	if x != nil {
		return x.Tp
	}
	return nil
}

func (x *AttributeProto) GetFloats() []float32 {
	if x != nil {
		return x.Floats
	}
	return nil
}

func (x *AttributeProto) GetInts() []int64 {
	if x != nil {
		return x.Ints
	}
	return nil
}

func (x *AttributeProto) GetStrings() [][]byte {
	if x != nil {
		return x.Strings
	}
	return nil
}

func (x *AttributeProto) GetTensors() []*TensorProto {
	if x != nil {
		return x.Tensors
	}
	return nil
}

func (x *AttributeProto) GetGraphs() []*GraphProto {
	if x != nil {
		return x.Graphs
	}
	return nil
}

func (x *AttributeProto) GetSparseTensors() []*SparseTensorProto {
	if x != nil {
		return x.SparseTensors
	}
	return nil
}

func (x *AttributeProto) GetTypeProtos() []*TypeProto {
	if x != nil {
		return x.TypeProtos
	}
	return nil
}

type ValueInfoProto struct {
	state         protoimpl.MessageState    `protogen:"open.v1"`
	Name          *string                   `protobuf:"bytes,1,opt,name=name" json:"name,omitempty"`
	Type          *TypeProto                `protobuf:"bytes,2,opt,name=type" json:"type,omitempty"`
	DocString     *string                   `protobuf:"bytes,3,opt,name=doc_string,json=docString" json:"doc_string,omitempty"`
	MetadataProps []*StringStringEntryProto `protobuf:"bytes,4,rep,name=metadata_props,json=metadataProps" json:"metadata_props,omitempty"`
	unknownFields protoimpl.UnknownFields
	sizeCache     protoimpl.SizeCache
}

func (x *ValueInfoProto) Reset() {
	*x = ValueInfoProto{}
	mi := &file_onnx_proto_msgTypes[1]
	ms := protoimpl.X.MessageStateOf(protoimpl.Pointer(x))
	ms.StoreMessageInfo(mi)
}

func (x *ValueInfoProto) String() string {
	return protoimpl.X.MessageStringOf(x)
}

func (*ValueInfoProto) ProtoMessage() {}

func (x *ValueInfoProto) ProtoReflect() protoreflect.Message {
	mi := &file_onnx_proto_msgTypes[1]
	if x != nil {
		ms := protoimpl.X.MessageStateOf(protoimpl.Pointer(x))
		if ms.LoadMessageInfo() == nil {
			ms.StoreMessageInfo(mi)
		}
		return ms
	}
	return mi.MessageOf(x)
}

func (*ValueInfoProto) Descriptor() ([]byte, []int) {
	return file_onnx_proto_rawDescGZIP(), []int{1}
}

func (x *ValueInfoProto) GetName() string {
	if x != nil && x.Name != nil {
		return *x.Name
	}
	return ""
}

func (x *ValueInfoProto) GetType() *TypeProto {
	if x != nil {
		return x.Type
	}
	return nil
}

func (x *ValueInfoProto) GetDocString() string {
	if x != nil && x.DocString != nil {
		return *x.DocString
	}
	return ""
}

func (x *ValueInfoProto) GetMetadataProps() []*StringStringEntryProto {
	if x != nil {
		return x.MetadataProps
	}
	return nil
}

type NodeProto struct {
	state                protoimpl.MessageState          `protogen:"open.v1"`
	Input                []string                        `protobuf:"bytes,1,rep,name=input" json:"input,omitempty"`
	Output               []string                        `protobuf:"bytes,2,rep,name=output" json:"output,omitempty"`
	Name                 *string                         `protobuf:"bytes,3,opt,name=name" json:"name,omitempty"`
	OpType               *string                         `protobuf:"bytes,4,opt,name=op_type,json=opType" json:"op_type,omitempty"`
	Domain               *string                         `protobuf:"bytes,7,opt,name=domain" json:"domain,omitempty"`
	Overload             *string                         `protobuf:"bytes,8,opt,name=overload" json:"overload,omitempty"`
	Attribute            []*AttributeProto               `protobuf:"bytes,5,rep,name=attribute" json:"attribute,omitempty"`
	DocString            *string                         `protobuf:"bytes,6,opt,name=doc_string,json=docString" json:"doc_string,omitempty"`
	MetadataProps        []*StringStringEntryProto       `protobuf:"bytes,9,rep,name=metadata_props,json=metadataProps" json:"metadata_props,omitempty"`
	DeviceConfigurations []*NodeDeviceConfigurationProto `protobuf:"bytes,10,rep,name=device_configurations,json=deviceConfigurations" json:"device_configurations,omitempty"`
	unknownFields        protoimpl.UnknownFields
	sizeCache            protoimpl.SizeCache
}

func (x *NodeProto) Reset() {
	*x = NodeProto{}
	mi := &file_onnx_proto_msgTypes[2]
	ms := protoimpl.X.MessageStateOf(protoimpl.Pointer(x))
	ms.StoreMessageInfo(mi)
}

func (x *NodeProto) String() string {
	return protoimpl.X.MessageStringOf(x)
}

func (*NodeProto) ProtoMessage() {}

func (x *NodeProto) ProtoReflect() protoreflect.Message {
	mi := &file_onnx_proto_msgTypes[2]
	if x != nil {
		ms := protoimpl.X.MessageStateOf(protoimpl.Pointer(x))
		if ms.LoadMessageInfo() == nil {
			ms.StoreMessageInfo(mi)
		}
		return ms
	}
	return mi.MessageOf(x)
}

func (*NodeProto) Descriptor() ([]byte, []int) {
	return file_onnx_proto_rawDescGZIP(), []int{2}
}

func (x *NodeProto) GetInput() []string {
	if x != nil {
		return x.Input
	}
	return nil
}

func (x *NodeProto) GetOutput() []string {
	if x != nil {
		return x.Output
	}
	return nil
}

func (x *NodeProto) GetName() string {
	if x != nil && x.Name != nil {
		return *x.Name
	}
	return ""
}

func (x *NodeProto) GetOpType() string {
	if x != nil && x.OpType != nil {
		return *x.OpType
	}
	return ""
}

func (x *NodeProto) GetDomain() string {
	if x != nil && x.Domain != nil {
		return *x.Domain
	}
	return ""
}

func (x *NodeProto) GetOverload() string {
	if x != nil && x.Overload != nil {
		return *x.Overload
	}
	return ""
}

func (x *NodeProto) GetAttribute() []*AttributeProto {
	if x != nil {
		return x.Attribute
	}
	return nil
}

func (x *NodeProto) GetDocString() string {
	if x != nil && x.DocString != nil {
		return *x.DocString
	}
	return ""
}

func (x *NodeProto) GetMetadataProps() []*StringStringEntryProto {
	if x != nil {
		return x.MetadataProps
	}
	return nil
}

func (x *NodeProto) GetDeviceConfigurations() []*NodeDeviceConfigurationProto {
	if x != nil {
		return x.DeviceConfigurations
	}
	return nil
}

type IntIntListEntryProto struct {
	state         protoimpl.MessageState `protogen:"open.v1"`
	Key           *int64                 `protobuf:"varint,1,opt,name=key" json:"key,omitempty"`
	Value         []int64                `protobuf:"varint,2,rep,name=value" json:"value,omitempty"`
	unknownFields protoimpl.UnknownFields
	sizeCache     protoimpl.SizeCache
}

func (x *IntIntListEntryProto) Reset() {
	*x = IntIntListEntryProto{}
	mi := &file_onnx_proto_msgTypes[3]
	ms := protoimpl.X.MessageStateOf(protoimpl.Pointer(x))
	ms.StoreMessageInfo(mi)
}

func (x *IntIntListEntryProto) String() string {
	return protoimpl.X.MessageStringOf(x)
}

func (*IntIntListEntryProto) ProtoMessage() {}

func (x *IntIntListEntryProto) ProtoReflect() protoreflect.Message {
	mi := &file_onnx_proto_msgTypes[3]
	if x != nil {
		ms := protoimpl.X.MessageStateOf(protoimpl.Pointer(x))
		if ms.LoadMessageInfo() == nil {
			ms.StoreMessageInfo(mi)
		}
		return ms
	}
	return mi.MessageOf(x)
}

func (*IntIntListEntryProto) Descriptor() ([]byte, []int) {
	return file_onnx_proto_rawDescGZIP(), []int{3}
}

func (x *IntIntListEntryProto) GetKey() int64 {
	if x != nil && x.Key != nil {
		return *x.Key
	}
	return 0
}

func (x *IntIntListEntryProto) GetValue() []int64 {
	if x != nil {
		return x.Value
	}
	return nil
}

type NodeDeviceConfigurationProto struct {
	state           protoimpl.MessageState `protogen:"open.v1"`
	ConfigurationId *string                `protobuf:"bytes,1,opt,name=configuration_id,json=configurationId" json:"configuration_id,omitempty"`
	ShardingSpec    []*ShardingSpecProto   `protobuf:"bytes,2,rep,name=sharding_spec,json=shardingSpec" json:"sharding_spec,omitempty"`
	PipelineStage   *int32                 `protobuf:"varint,3,opt,name=pipeline_stage,json=pipelineStage" json:"pipeline_stage,omitempty"`
	unknownFields   protoimpl.UnknownFields
	sizeCache       protoimpl.SizeCache
}

func (x *NodeDeviceConfigurationProto) Reset() {
	*x = NodeDeviceConfigurationProto{}
	mi := &file_onnx_proto_msgTypes[4]
	ms := protoimpl.X.MessageStateOf(protoimpl.Pointer(x))
	ms.StoreMessageInfo(mi)
}

func (x *NodeDeviceConfigurationProto) String() string {
	return protoimpl.X.MessageStringOf(x)
}

func (*NodeDeviceConfigurationProto) ProtoMessage() {}

func (x *NodeDeviceConfigurationProto) ProtoReflect() protoreflect.Message {
	mi := &file_onnx_proto_msgTypes[4]
	if x != nil {
		ms := protoimpl.X.MessageStateOf(protoimpl.Pointer(x))
		if ms.LoadMessageInfo() == nil {
			ms.StoreMessageInfo(mi)
		}
		return ms
	}
	return mi.MessageOf(x)
}

func (*NodeDeviceConfigurationProto) Descriptor() ([]byte, []int) {
	return file_onnx_proto_rawDescGZIP(), []int{4}
}

func (x *NodeDeviceConfigurationProto) GetConfigurationId() string {
	if x != nil && x.ConfigurationId != nil {
		return *x.ConfigurationId
	}
	return ""
}

func (x *NodeDeviceConfigurationProto) GetShardingSpec() []*ShardingSpecProto {
	if x != nil {
		return x.ShardingSpec
	}
	return nil
}

func (x *NodeDeviceConfigurationProto) GetPipelineStage() int32 {
	if x != nil && x.PipelineStage != nil {
		return *x.PipelineStage
	}
	return 0
}

type ShardingSpecProto struct {
	state                 protoimpl.MessageState  `protogen:"open.v1"`
	TensorName            *string                 `protobuf:"bytes,1,opt,name=tensor_name,json=tensorName" json:"tensor_name,omitempty"`
	Device                []int64                 `protobuf:"varint,2,rep,name=device" json:"device,omitempty"`
	IndexToDeviceGroupMap []*IntIntListEntryProto `protobuf:"bytes,3,rep,name=index_to_device_group_map,json=indexToDeviceGroupMap" json:"index_to_device_group_map,omitempty"`
	ShardedDim            []*ShardedDimProto      `protobuf:"bytes,4,rep,name=sharded_dim,json=shardedDim" json:"sharded_dim,omitempty"`
	unknownFields         protoimpl.UnknownFields
	sizeCache             protoimpl.SizeCache
}

func (x *ShardingSpecProto) Reset() {
	*x = ShardingSpecProto{}
	mi := &file_onnx_proto_msgTypes[5]
	ms := protoimpl.X.MessageStateOf(protoimpl.Pointer(x))
	ms.StoreMessageInfo(mi)
}

func (x *ShardingSpecProto) String() string {
	return protoimpl.X.MessageStringOf(x)
}

func (*ShardingSpecProto) ProtoMessage() {}

func (x *ShardingSpecProto) ProtoReflect() protoreflect.Message {
	mi := &file_onnx_proto_msgTypes[5]
	if x != nil {
		ms := protoimpl.X.MessageStateOf(protoimpl.Pointer(x))
		if ms.LoadMessageInfo() == nil {
			ms.StoreMessageInfo(mi)
		}
		return ms
	}
	return mi.MessageOf(x)
}

func (*ShardingSpecProto) Descriptor() ([]byte, []int) {
	return file_onnx_proto_rawDescGZIP(), []int{5}
}

func (x *ShardingSpecProto) GetTensorName() string {
	if x != nil && x.TensorName != nil {
		return *x.TensorName
	}
	return ""
}

func (x *ShardingSpecProto) GetDevice() []int64 {
	if x != nil {
		return x.Device
	}
	return nil
}

func (x *ShardingSpecProto) GetIndexToDeviceGroupMap() []*IntIntListEntryProto {
	if x != nil {
		return x.IndexToDeviceGroupMap
	}
	return nil
}

func (x *ShardingSpecProto) GetShardedDim() []*ShardedDimProto {
	if x != nil {
		return x.ShardedDim
	}
	return nil
}

type ShardedDimProto struct {
	state          protoimpl.MessageState   `protogen:"open.v1"`
	Axis           *int64                   `protobuf:"varint,1,opt,name=axis" json:"axis,omitempty"`
	SimpleSharding []*SimpleShardedDimProto `protobuf:"bytes,2,rep,name=simple_sharding,json=simpleSharding" json:"simple_sharding,omitempty"`
	unknownFields  protoimpl.UnknownFields
	sizeCache      protoimpl.SizeCache
}

func (x *ShardedDimProto) Reset() {
	*x = ShardedDimProto{}
	mi := &file_onnx_proto_msgTypes[6]
	ms := protoimpl.X.MessageStateOf(protoimpl.Pointer(x))
	ms.StoreMessageInfo(mi)
}

func (x *ShardedDimProto) String() string {
	return protoimpl.X.MessageStringOf(x)
}

func (*ShardedDimProto) ProtoMessage() {}

func (x *ShardedDimProto) ProtoReflect() protoreflect.Message {
	mi := &file_onnx_proto_msgTypes[6]
	if x != nil {
		ms := protoimpl.X.MessageStateOf(protoimpl.Pointer(x))
		if ms.LoadMessageInfo() == nil {
			ms.StoreMessageInfo(mi)
		}
		return ms
	}
	return mi.MessageOf(x)
}

func (*ShardedDimProto) Descriptor() ([]byte, []int) {
	return file_onnx_proto_rawDescGZIP(), []int{6}
}

func (x *ShardedDimProto) GetAxis() int64 {
	if x != nil && x.Axis != nil {
		return *x.Axis
	}
	return 0
}

func (x *ShardedDimProto) GetSimpleSharding() []*SimpleShardedDimProto {
	if x != nil {
		return x.SimpleSharding
	}
	return nil
}

type SimpleShardedDimProto struct {
	state protoimpl.MessageState `protogen:"open.v1"`
	Dim           isSimpleShardedDimProto_Dim `protobuf_oneof:"dim"`
	NumShards     *int64                      `protobuf:"varint,3,opt,name=num_shards,json=numShards" json:"num_shards,omitempty"`
	unknownFields protoimpl.UnknownFields
	sizeCache     protoimpl.SizeCache
}

func (x *SimpleShardedDimProto) Reset() {
	*x = SimpleShardedDimProto{}
	mi := &file_onnx_proto_msgTypes[7]
	ms := protoimpl.X.MessageStateOf(protoimpl.Pointer(x))
	ms.StoreMessageInfo(mi)
}

func (x *SimpleShardedDimProto) String() string {
	return protoimpl.X.MessageStringOf(x)
}

func (*SimpleShardedDimProto) ProtoMessage() {}

func (x *SimpleShardedDimProto) ProtoReflect() protoreflect.Message {
	mi := &file_onnx_proto_msgTypes[7]
	if x != nil {
		ms := protoimpl.X.MessageStateOf(protoimpl.Pointer(x))
		if ms.LoadMessageInfo() == nil {
			ms.StoreMessageInfo(mi)
		}
		return ms
	}
	return mi.MessageOf(x)
}

func (*SimpleShardedDimProto) Descriptor() ([]byte, []int) {
	return file_onnx_proto_rawDescGZIP(), []int{7}
}

func (x *SimpleShardedDimProto) GetDim() isSimpleShardedDimProto_Dim {
	if x != nil {
		return x.Dim
	}
	return nil
}

func (x *SimpleShardedDimProto) GetDimValue() int64 {
	if x != nil {
		if x, ok := x.Dim.(*SimpleShardedDimProto_DimValue); ok {
			return x.DimValue
		}
	}
	return 0
}

func (x *SimpleShardedDimProto) GetDimParam() string {
	if x != nil {
		if x, ok := x.Dim.(*SimpleShardedDimProto_DimParam); ok {
			return x.DimParam
		}
	}
	return ""
}

func (x *SimpleShardedDimProto) GetNumShards() int64 {
	if x != nil && x.NumShards != nil {
		return *x.NumShards
	}
	return 0
}

type isSimpleShardedDimProto_Dim interface {
	isSimpleShardedDimProto_Dim()
}

type SimpleShardedDimProto_DimValue struct {
	DimValue int64 `protobuf:"varint,1,opt,name=dim_value,json=dimValue,oneof"`
}

type SimpleShardedDimProto_DimParam struct {
	DimParam string `protobuf:"bytes,2,opt,name=dim_param,json=dimParam,oneof"`
}

func (*SimpleShardedDimProto_DimValue) isSimpleShardedDimProto_Dim() {}

func (*SimpleShardedDimProto_DimParam) isSimpleShardedDimProto_Dim() {}

type TrainingInfoProto struct {
	state                 protoimpl.MessageState    `protogen:"open.v1"`
	Initialization        *GraphProto               `protobuf:"bytes,1,opt,name=initialization" json:"initialization,omitempty"`
	Algorithm             *GraphProto               `protobuf:"bytes,2,opt,name=algorithm" json:"algorithm,omitempty"`
	InitializationBinding []*StringStringEntryProto `protobuf:"bytes,3,rep,name=initialization_binding,json=initializationBinding" json:"initialization_binding,omitempty"`
	UpdateBinding         []*StringStringEntryProto `protobuf:"bytes,4,rep,name=update_binding,json=updateBinding" json:"update_binding,omitempty"`
	unknownFields         protoimpl.UnknownFields
	sizeCache             protoimpl.SizeCache
}

func (x *TrainingInfoProto) Reset() {
	*x = TrainingInfoProto{}
	mi := &file_onnx_proto_msgTypes[8]
	ms := protoimpl.X.MessageStateOf(protoimpl.Pointer(x))
	ms.StoreMessageInfo(mi)
}

func (x *TrainingInfoProto) String() string {
	return protoimpl.X.MessageStringOf(x)
}

func (*TrainingInfoProto) ProtoMessage() {}

func (x *TrainingInfoProto) ProtoReflect() protoreflect.Message {
	mi := &file_onnx_proto_msgTypes[8]
	if x != nil {
		ms := protoimpl.X.MessageStateOf(protoimpl.Pointer(x))
		if ms.LoadMessageInfo() == nil {
			ms.StoreMessageInfo(mi)
		}
		return ms
	}
	return mi.MessageOf(x)
}

func (*TrainingInfoProto) Descriptor() ([]byte, []int) {
	return file_onnx_proto_rawDescGZIP(), []int{8}
}

func (x *TrainingInfoProto) GetInitialization() *GraphProto {
	if x != nil {
		return x.Initialization
	}
	return nil
}

func (x *TrainingInfoProto) GetAlgorithm() *GraphProto {
	if x != nil {
		return x.Algorithm
	}
	return nil
}

func (x *TrainingInfoProto) GetInitializationBinding() []*StringStringEntryProto {
	if x != nil {
		return x.InitializationBinding
	}
	return nil
}

func (x *TrainingInfoProto) GetUpdateBinding() []*StringStringEntryProto {
	if x != nil {
		return x.UpdateBinding
	}
	return nil
}

type ModelProto struct {
	state           protoimpl.MessageState      `protogen:"open.v1"`
	IrVersion       *int64                      `protobuf:"varint,1,opt,name=ir_version,json=irVersion" json:"ir_version,omitempty"`
	OpsetImport     []*OperatorSetIdProto       `protobuf:"bytes,8,rep,name=opset_import,json=opsetImport" json:"opset_import,omitempty"`
	ProducerName    *string                     `protobuf:"bytes,2,opt,name=producer_name,json=producerName" json:"producer_name,omitempty"`
	ProducerVersion *string                     `protobuf:"bytes,3,opt,name=producer_version,json=producerVersion" json:"producer_version,omitempty"`
	Domain          *string                     `protobuf:"bytes,4,opt,name=domain" json:"domain,omitempty"`
	ModelVersion    *int64                      `protobuf:"varint,5,opt,name=model_version,json=modelVersion" json:"model_version,omitempty"`
	DocString       *string                     `protobuf:"bytes,6,opt,name=doc_string,json=docString" json:"doc_string,omitempty"`
	Graph           *GraphProto                 `protobuf:"bytes,7,opt,name=graph" json:"graph,omitempty"`
	MetadataProps   []*StringStringEntryProto   `protobuf:"bytes,14,rep,name=metadata_props,json=metadataProps" json:"metadata_props,omitempty"`
	TrainingInfo    []*TrainingInfoProto        `protobuf:"bytes,20,rep,name=training_info,json=trainingInfo" json:"training_info,omitempty"`
	Functions       []*FunctionProto            `protobuf:"bytes,25,rep,name=functions" json:"functions,omitempty"`
	Configuration   []*DeviceConfigurationProto `protobuf:"bytes,26,rep,name=configuration" json:"configuration,omitempty"`
	unknownFields   protoimpl.UnknownFields
	sizeCache       protoimpl.SizeCache
}

func (x *ModelProto) Reset() {
	*x = ModelProto{}
	mi := &file_onnx_proto_msgTypes[9]
	ms := protoimpl.X.MessageStateOf(protoimpl.Pointer(x))
	ms.StoreMessageInfo(mi)
}

func (x *ModelProto) String() string {
	return protoimpl.X.MessageStringOf(x)
}

func (*ModelProto) ProtoMessage() {}

func (x *ModelProto) ProtoReflect() protoreflect.Message {
	mi := &file_onnx_proto_msgTypes[9]
	if x != nil {
		ms := protoimpl.X.MessageStateOf(protoimpl.Pointer(x))
		if ms.LoadMessageInfo() == nil {
			ms.StoreMessageInfo(mi)
		}
		return ms
	}
	return mi.MessageOf(x)
}

func (*ModelProto) Descriptor() ([]byte, []int) {
	return file_onnx_proto_rawDescGZIP(), []int{9}
}

func (x *ModelProto) GetIrVersion() int64 {
	if x != nil && x.IrVersion != nil {
		return *x.IrVersion
	}
	return 0
}

func (x *ModelProto) GetOpsetImport() []*OperatorSetIdProto {
	if x != nil {
		return x.OpsetImport
	}
	return nil
}

func (x *ModelProto) GetProducerName() string {
	if x != nil && x.ProducerName != nil {
		return *x.ProducerName
	}
	return ""
}

func (x *ModelProto) GetProducerVersion() string {
	if x != nil && x.ProducerVersion != nil {
		return *x.ProducerVersion
	}
	return ""
}

func (x *ModelProto) GetDomain() string {
	if x != nil && x.Domain != nil {
		return *x.Domain
	}
	return ""
}

func (x *ModelProto) GetModelVersion() int64 {
	if x != nil && x.ModelVersion != nil {
		return *x.ModelVersion
	}
	return 0
}

func (x *ModelProto) GetDocString() string {
	if x != nil && x.DocString != nil {
		return *x.DocString
	}
	return ""
}

func (x *ModelProto) GetGraph() *GraphProto {
	if x != nil {
		return x.Graph
	}
	return nil
}

func (x *ModelProto) GetMetadataProps() []*StringStringEntryProto {
	if x != nil {
		return x.MetadataProps
	}
	return nil
}

func (x *ModelProto) GetTrainingInfo() []*TrainingInfoProto {
	if x != nil {
		return x.TrainingInfo
	}
	return nil
}

func (x *ModelProto) GetFunctions() []*FunctionProto {
	if x != nil {
		return x.Functions
	}
	return nil
}

func (x *ModelProto) GetConfiguration() []*DeviceConfigurationProto {
	if x != nil {
		return x.Configuration
	}
	return nil
}

type DeviceConfigurationProto struct {
	state         protoimpl.MessageState `protogen:"open.v1"`
	Name          *string                `protobuf:"bytes,1,opt,name=name" json:"name,omitempty"`
	NumDevices    *int32                 `protobuf:"varint,2,opt,name=num_devices,json=numDevices" json:"num_devices,omitempty"`
	Device        []string               `protobuf:"bytes,3,rep,name=device" json:"device,omitempty"`
	unknownFields protoimpl.UnknownFields
	sizeCache     protoimpl.SizeCache
}

func (x *DeviceConfigurationProto) Reset() {
	*x = DeviceConfigurationProto{}
	mi := &file_onnx_proto_msgTypes[10]
	ms := protoimpl.X.MessageStateOf(protoimpl.Pointer(x))
	ms.StoreMessageInfo(mi)
}

func (x *DeviceConfigurationProto) String() string {
	return protoimpl.X.MessageStringOf(x)
}

func (*DeviceConfigurationProto) ProtoMessage() {}

func (x *DeviceConfigurationProto) ProtoReflect() protoreflect.Message {
	mi := &file_onnx_proto_msgTypes[10]
	if x != nil {
		ms := protoimpl.X.MessageStateOf(protoimpl.Pointer(x))
		if ms.LoadMessageInfo() == nil {
			ms.StoreMessageInfo(mi)
		}
		return ms
	}
	return mi.MessageOf(x)
}

func (*DeviceConfigurationProto) Descriptor() ([]byte, []int) {
	return file_onnx_proto_rawDescGZIP(), []int{10}
}

func (x *DeviceConfigurationProto) GetName() string {
	if x != nil && x.Name != nil {
		return *x.Name
	}
	return ""
}

func (x *DeviceConfigurationProto) GetNumDevices() int32 {
	if x != nil && x.NumDevices != nil {
		return *x.NumDevices
	}
	return 0
}

func (x *DeviceConfigurationProto) GetDevice() []string {
	if x != nil {
		return x.Device
	}
	return nil
}

type StringStringEntryProto struct {
	state         protoimpl.MessageState `protogen:"open.v1"`
	Key           *string                `protobuf:"bytes,1,opt,name=key" json:"key,omitempty"`
	Value         *string                `protobuf:"bytes,2,opt,name=value" json:"value,omitempty"`
	unknownFields protoimpl.UnknownFields
	sizeCache     protoimpl.SizeCache
}

func (x *StringStringEntryProto) Reset() {
	*x = StringStringEntryProto{}
	mi := &file_onnx_proto_msgTypes[11]
	ms := protoimpl.X.MessageStateOf(protoimpl.Pointer(x))
	ms.StoreMessageInfo(mi)
}

func (x *StringStringEntryProto) String() string {
	return protoimpl.X.MessageStringOf(x)
}

func (*StringStringEntryProto) ProtoMessage() {}

func (x *StringStringEntryProto) ProtoReflect() protoreflect.Message {
	mi := &file_onnx_proto_msgTypes[11]
	if x != nil {
		ms := protoimpl.X.MessageStateOf(protoimpl.Pointer(x))
		if ms.LoadMessageInfo() == nil {
			ms.StoreMessageInfo(mi)
		}
		return ms
	}
	return mi.MessageOf(x)
}

func (*StringStringEntryProto) Descriptor() ([]byte, []int) {
	return file_onnx_proto_rawDescGZIP(), []int{11}
}

func (x *StringStringEntryProto) GetKey() string {
	if x != nil && x.Key != nil {
		return *x.Key
	}
	return ""
}

func (x *StringStringEntryProto) GetValue() string {
	if x != nil && x.Value != nil {
		return *x.Value
	}
	return ""
}

type TensorAnnotation struct {
	state                     protoimpl.MessageState    `protogen:"open.v1"`
	TensorName                *string                   `protobuf:"bytes,1,opt,name=tensor_name,json=tensorName" json:"tensor_name,omitempty"`
	QuantParameterTensorNames []*StringStringEntryProto `protobuf:"bytes,2,rep,name=quant_parameter_tensor_names,json=quantParameterTensorNames" json:"quant_parameter_tensor_names,omitempty"`
	unknownFields             protoimpl.UnknownFields
	sizeCache                 protoimpl.SizeCache
}

func (x *TensorAnnotation) Reset() {
	*x = TensorAnnotation{}
	mi := &file_onnx_proto_msgTypes[12]
	ms := protoimpl.X.MessageStateOf(protoimpl.Pointer(x))
	ms.StoreMessageInfo(mi)
}

func (x *TensorAnnotation) String() string {
	return protoimpl.X.MessageStringOf(x)
}

func (*TensorAnnotation) ProtoMessage() {}

func (x *TensorAnnotation) ProtoReflect() protoreflect.Message {
	mi := &file_onnx_proto_msgTypes[12]
	if x != nil {
		ms := protoimpl.X.MessageStateOf(protoimpl.Pointer(x))
		if ms.LoadMessageInfo() == nil {
			ms.StoreMessageInfo(mi)
		}
		return ms
	}
	return mi.MessageOf(x)
}

func (*TensorAnnotation) Descriptor() ([]byte, []int) {
	return file_onnx_proto_rawDescGZIP(), []int{12}
}

func (x *TensorAnnotation) GetTensorName() string {
	if x != nil && x.TensorName != nil {
		return *x.TensorName
	}
	return ""
}

func (x *TensorAnnotation) GetQuantParameterTensorNames() []*StringStringEntryProto {
	if x != nil {
		return x.QuantParameterTensorNames
	}
	return nil
}

type GraphProto struct {
	state                  protoimpl.MessageState    `protogen:"open.v1"`
	Node                   []*NodeProto              `protobuf:"bytes,1,rep,name=node" json:"node,omitempty"`
	Name                   *string                   `protobuf:"bytes,2,opt,name=name" json:"name,omitempty"`
	Initializer            []*TensorProto            `protobuf:"bytes,5,rep,name=initializer" json:"initializer,omitempty"`
	SparseInitializer      []*SparseTensorProto      `protobuf:"bytes,15,rep,name=sparse_initializer,json=sparseInitializer" json:"sparse_initializer,omitempty"`
	DocString              *string                   `protobuf:"bytes,10,opt,name=doc_string,json=docString" json:"doc_string,omitempty"`
	Input                  []*ValueInfoProto         `protobuf:"bytes,11,rep,name=input" json:"input,omitempty"`
	Output                 []*ValueInfoProto         `protobuf:"bytes,12,rep,name=output" json:"output,omitempty"`
	ValueInfo              []*ValueInfoProto         `protobuf:"bytes,13,rep,name=value_info,json=valueInfo" json:"value_info,omitempty"`
	QuantizationAnnotation []*TensorAnnotation       `protobuf:"bytes,14,rep,name=quantization_annotation,json=quantizationAnnotation" json:"quantization_annotation,omitempty"`
	MetadataProps          []*StringStringEntryProto `protobuf:"bytes,16,rep,name=metadata_props,json=metadataProps" json:"metadata_props,omitempty"`
	unknownFields          protoimpl.UnknownFields
	sizeCache              protoimpl.SizeCache
}

func (x *GraphProto) Reset() {
	*x = GraphProto{}
	mi := &file_onnx_proto_msgTypes[13]
	ms := protoimpl.X.MessageStateOf(protoimpl.Pointer(x))
	ms.StoreMessageInfo(mi)
}

func (x *GraphProto) String() string {
	return protoimpl.X.MessageStringOf(x)
}

func (*GraphProto) ProtoMessage() {}

func (x *GraphProto) ProtoReflect() protoreflect.Message {
	mi := &file_onnx_proto_msgTypes[13]
	if x != nil {
		ms := protoimpl.X.MessageStateOf(protoimpl.Pointer(x))
		if ms.LoadMessageInfo() == nil {
			ms.StoreMessageInfo(mi)
		}
		return ms
	}
	return mi.MessageOf(x)
}

func (*GraphProto) Descriptor() ([]byte, []int) {
	return file_onnx_proto_rawDescGZIP(), []int{13}
}

func (x *GraphProto) GetNode() []*NodeProto {
	if x != nil {
		return x.Node
	}
	return nil
}

func (x *GraphProto) GetName() string {
	if x != nil && x.Name != nil {
		return *x.Name
	}
	return ""
}

func (x *GraphProto) GetInitializer() []*TensorProto {
	if x != nil {
		return x.Initializer
	}
	return nil
}

func (x *GraphProto) GetSparseInitializer() []*SparseTensorProto {
	if x != nil {
		return x.SparseInitializer
	}
	return nil
}

func (x *GraphProto) GetDocString() string {
	if x != nil && x.DocString != nil {
		return *x.DocString
	}
	return ""
}

func (x *GraphProto) GetInput() []*ValueInfoProto {
	if x != nil {
		return x.Input
	}
	return nil
}

func (x *GraphProto) GetOutput() []*ValueInfoProto {
	if x != nil {
		return x.Output
	}
	return nil
}

func (x *GraphProto) GetValueInfo() []*ValueInfoProto {
	if x != nil {
		return x.ValueInfo
	}
	return nil
}

func (x *GraphProto) GetQuantizationAnnotation() []*TensorAnnotation {
	if x != nil {
		return x.QuantizationAnnotation
	}
	return nil
}

func (x *GraphProto) GetMetadataProps() []*StringStringEntryProto {
	if x != nil {
		return x.MetadataProps
	}
	return nil
}

type TensorProto struct {
	state         protoimpl.MessageState    `protogen:"open.v1"`
	Dims          []int64                   `protobuf:"varint,1,rep,name=dims" json:"dims,omitempty"`
	DataType      *int32                    `protobuf:"varint,2,opt,name=data_type,json=dataType" json:"data_type,omitempty"`
	Segment       *TensorProto_Segment      `protobuf:"bytes,3,opt,name=segment" json:"segment,omitempty"`
	FloatData     []float32                 `protobuf:"fixed32,4,rep,packed,name=float_data,json=floatData" json:"float_data,omitempty"`
	Int32Data     []int32                   `protobuf:"varint,5,rep,packed,name=int32_data,json=int32Data" json:"int32_data,omitempty"`
	StringData    [][]byte                  `protobuf:"bytes,6,rep,name=string_data,json=stringData" json:"string_data,omitempty"`
	Int64Data     []int64                   `protobuf:"varint,7,rep,packed,name=int64_data,json=int64Data" json:"int64_data,omitempty"`
	Name          *string                   `protobuf:"bytes,8,opt,name=name" json:"name,omitempty"`
	DocString     *string                   `protobuf:"bytes,12,opt,name=doc_string,json=docString" json:"doc_string,omitempty"`
	RawData       []byte                    `protobuf:"bytes,9,opt,name=raw_data,json=rawData" json:"raw_data,omitempty"`
	ExternalData  []*StringStringEntryProto `protobuf:"bytes,13,rep,name=external_data,json=externalData" json:"external_data,omitempty"`
	DataLocation  *TensorProto_DataLocation `protobuf:"varint,14,opt,name=data_location,json=dataLocation,enum=onnx.TensorProto_DataLocation" json:"data_location,omitempty"`
	DoubleData    []float64                 `protobuf:"fixed64,10,rep,packed,name=double_data,json=doubleData" json:"double_data,omitempty"`
	Uint64Data    []uint64                  `protobuf:"varint,11,rep,packed,name=uint64_data,json=uint64Data" json:"uint64_data,omitempty"`
	MetadataProps []*StringStringEntryProto `protobuf:"bytes,16,rep,name=metadata_props,json=metadataProps" json:"metadata_props,omitempty"`
	unknownFields protoimpl.UnknownFields
	sizeCache     protoimpl.SizeCache
}

func (x *TensorProto) Reset() {
	*x = TensorProto{}
	mi := &file_onnx_proto_msgTypes[14]
	ms := protoimpl.X.MessageStateOf(protoimpl.Pointer(x))
	ms.StoreMessageInfo(mi)
}

func (x *TensorProto) String() string {
	return protoimpl.X.MessageStringOf(x)
}

func (*TensorProto) ProtoMessage() {}

func (x *TensorProto) ProtoReflect() protoreflect.Message {
	mi := &file_onnx_proto_msgTypes[14]
	if x != nil {
		ms := protoimpl.X.MessageStateOf(protoimpl.Pointer(x))
		if ms.LoadMessageInfo() == nil {
			ms.StoreMessageInfo(mi)
		}
		return ms
	}
	return mi.MessageOf(x)
}

func (*TensorProto) Descriptor() ([]byte, []int) {
	return file_onnx_proto_rawDescGZIP(), []int{14}
}

func (x *TensorProto) GetDims() []int64 {
	if x != nil {
		return x.Dims
	}
	return nil
}

func (x *TensorProto) GetDataType() int32 {
	if x != nil && x.DataType != nil {
		return *x.DataType
	}
	return 0
}

func (x *TensorProto) GetSegment() *TensorProto_Segment {
	if x != nil {
		return x.Segment
	}
	return nil
}

func (x *TensorProto) GetFloatData() []float32 {
	if x != nil {
		return x.FloatData
	}
	return nil
}

func (x *TensorProto) GetInt32Data() []int32 {
	if x != nil {
		return x.Int32Data
	}
	return nil
}

func (x *TensorProto) GetStringData() [][]byte {
	if x != nil {
		return x.StringData
	}
	return nil
}

func (x *TensorProto) GetInt64Data() []int64 {
	if x != nil {
		return x.Int64Data
	}
	return nil
}

func (x *TensorProto) GetName() string {
	if x != nil && x.Name != nil {
		return *x.Name
	}
	return ""
}

func (x *TensorProto) GetDocString() string {
	if x != nil && x.DocString != nil {
		return *x.DocString
	}
	return ""
}

func (x *TensorProto) GetRawData() []byte {
	if x != nil {
		return x.RawData
	}
	return nil
}

func (x *TensorProto) GetExternalData() []*StringStringEntryProto {
	if x != nil {
		return x.ExternalData
	}
	return nil
}

func (x *TensorProto) GetDataLocation() TensorProto_DataLocation {
	if x != nil && x.DataLocation != nil {
		return *x.DataLocation
	}
	return TensorProto_DEFAULT
}

func (x *TensorProto) GetDoubleData() []float64 {
	if x != nil {
		return x.DoubleData
	}
	return nil
}

func (x *TensorProto) GetUint64Data() []uint64 {
	if x != nil {
		return x.Uint64Data
	}
	return nil
}

func (x *TensorProto) GetMetadataProps() []*StringStringEntryProto {
	if x != nil {
		return x.MetadataProps
	}
	return nil
}

type SparseTensorProto struct {
	state         protoimpl.MessageState `protogen:"open.v1"`
	Values        *TensorProto           `protobuf:"bytes,1,opt,name=values" json:"values,omitempty"`
	Indices       *TensorProto           `protobuf:"bytes,2,opt,name=indices" json:"indices,omitempty"`
	Dims          []int64                `protobuf:"varint,3,rep,name=dims" json:"dims,omitempty"`
	unknownFields protoimpl.UnknownFields
	sizeCache     protoimpl.SizeCache
}

func (x *SparseTensorProto) Reset() {
	*x = SparseTensorProto{}
	mi := &file_onnx_proto_msgTypes[15]
	ms := protoimpl.X.MessageStateOf(protoimpl.Pointer(x))
	ms.StoreMessageInfo(mi)
}

func (x *SparseTensorProto) String() string {
	return protoimpl.X.MessageStringOf(x)
}

func (*SparseTensorProto) ProtoMessage() {}

func (x *SparseTensorProto) ProtoReflect() protoreflect.Message {
	mi := &file_onnx_proto_msgTypes[15]
	if x != nil {
		ms := protoimpl.X.MessageStateOf(protoimpl.Pointer(x))
		if ms.LoadMessageInfo() == nil {
			ms.StoreMessageInfo(mi)
		}
		return ms
	}
	return mi.MessageOf(x)
}

func (*SparseTensorProto) Descriptor() ([]byte, []int) {
	return file_onnx_proto_rawDescGZIP(), []int{15}
}

func (x *SparseTensorProto) GetValues() *TensorProto {
	if x != nil {
		return x.Values
	}
	return nil
}

func (x *SparseTensorProto) GetIndices() *TensorProto {
	if x != nil {
		return x.Indices
	}
	return nil
}

func (x *SparseTensorProto) GetDims() []int64 {
	if x != nil {
		return x.Dims
	}
	return nil
}

type TensorShapeProto struct {
	state         protoimpl.MessageState        `protogen:"open.v1"`
	Dim           []*TensorShapeProto_Dimension `protobuf:"bytes,1,rep,name=dim" json:"dim,omitempty"`
	unknownFields protoimpl.UnknownFields
	sizeCache     protoimpl.SizeCache
}

func (x *TensorShapeProto) Reset() {
	*x = TensorShapeProto{}
	mi := &file_onnx_proto_msgTypes[16]
	ms := protoimpl.X.MessageStateOf(protoimpl.Pointer(x))
	ms.StoreMessageInfo(mi)
}

func (x *TensorShapeProto) String() string {
	return protoimpl.X.MessageStringOf(x)
}

func (*TensorShapeProto) ProtoMessage() {}

func (x *TensorShapeProto) ProtoReflect() protoreflect.Message {
	mi := &file_onnx_proto_msgTypes[16]
	if x != nil {
		ms := protoimpl.X.MessageStateOf(protoimpl.Pointer(x))
		if ms.LoadMessageInfo() == nil {
			ms.StoreMessageInfo(mi)
		}
		return ms
	}
	return mi.MessageOf(x)
}

func (*TensorShapeProto) Descriptor() ([]byte, []int) {
	return file_onnx_proto_rawDescGZIP(), []int{16}
}

func (x *TensorShapeProto) GetDim() []*TensorShapeProto_Dimension {
	if x != nil {
		return x.Dim
	}
	return nil
}

type TypeProto struct {
	state protoimpl.MessageState `protogen:"open.v1"`
	Value         isTypeProto_Value `protobuf_oneof:"value"`
	Denotation    *string           `protobuf:"bytes,6,opt,name=denotation" json:"denotation,omitempty"`
	unknownFields protoimpl.UnknownFields
	sizeCache     protoimpl.SizeCache
}

func (x *TypeProto) Reset() {
	*x = TypeProto{}
	mi := &file_onnx_proto_msgTypes[17]
	ms := protoimpl.X.MessageStateOf(protoimpl.Pointer(x))
	ms.StoreMessageInfo(mi)
}

func (x *TypeProto) String() string {
	return protoimpl.X.MessageStringOf(x)
}

func (*TypeProto) ProtoMessage() {}

func (x *TypeProto) ProtoReflect() protoreflect.Message {
	mi := &file_onnx_proto_msgTypes[17]
	if x != nil {
		ms := protoimpl.X.MessageStateOf(protoimpl.Pointer(x))
		if ms.LoadMessageInfo() == nil {
			ms.StoreMessageInfo(mi)
		}
		return ms
	}
	return mi.MessageOf(x)
}

func (*TypeProto) Descriptor() ([]byte, []int) {
	return file_onnx_proto_rawDescGZIP(), []int{17}
}

func (x *TypeProto) GetValue() isTypeProto_Value {
	if x != nil {
		return x.Value
	}
	return nil
}

func (x *TypeProto) GetTensorType() *TypeProto_Tensor {
	if x != nil {
		if x, ok := x.Value.(*TypeProto_TensorType); ok {
			return x.TensorType
		}
	}
	return nil
}

func (x *TypeProto) GetSequenceType() *TypeProto_Sequence {
	if x != nil {
		if x, ok := x.Value.(*TypeProto_SequenceType); ok {
			return x.SequenceType
		}
	}
	return nil
}

func (x *TypeProto) GetMapType() *TypeProto_Map {
	if x != nil {
		if x, ok := x.Value.(*TypeProto_MapType); ok {
			return x.MapType
		}
	}
	return nil
}

func (x *TypeProto) GetOptionalType() *TypeProto_Optional {
	if x != nil {
		if x, ok := x.Value.(*TypeProto_OptionalType); ok {
			return x.OptionalType
		}
	}
	return nil
}

func (x *TypeProto) GetSparseTensorType() *TypeProto_SparseTensor {
	if x != nil {
		if x, ok := x.Value.(*TypeProto_SparseTensorType); ok {
			return x.SparseTensorType
		}
	}
	return nil
}

func (x *TypeProto) GetDenotation() string {
	if x != nil && x.Denotation != nil {
		return *x.Denotation
	}
	return ""
}

type isTypeProto_Value interface {
	isTypeProto_Value()
}

type TypeProto_TensorType struct {
	TensorType *TypeProto_Tensor `protobuf:"bytes,1,opt,name=tensor_type,json=tensorType,oneof"`
}

type TypeProto_SequenceType struct {
	SequenceType *TypeProto_Sequence `protobuf:"bytes,4,opt,name=sequence_type,json=sequenceType,oneof"`
}

type TypeProto_MapType struct {
	MapType *TypeProto_Map `protobuf:"bytes,5,opt,name=map_type,json=mapType,oneof"`
}

type TypeProto_OptionalType struct {
	OptionalType *TypeProto_Optional `protobuf:"bytes,9,opt,name=optional_type,json=optionalType,oneof"`
}

type TypeProto_SparseTensorType struct {
	SparseTensorType *TypeProto_SparseTensor `protobuf:"bytes,8,opt,name=sparse_tensor_type,json=sparseTensorType,oneof"`
}

func (*TypeProto_TensorType) isTypeProto_Value() {}

func (*TypeProto_SequenceType) isTypeProto_Value() {}

func (*TypeProto_MapType) isTypeProto_Value() {}

func (*TypeProto_OptionalType) isTypeProto_Value() {}

func (*TypeProto_SparseTensorType) isTypeProto_Value() {}

type OperatorSetIdProto struct {
	state         protoimpl.MessageState `protogen:"open.v1"`
	Domain        *string                `protobuf:"bytes,1,opt,name=domain" json:"domain,omitempty"`
	Version       *int64                 `protobuf:"varint,2,opt,name=version" json:"version,omitempty"`
	unknownFields protoimpl.UnknownFields
	sizeCache     protoimpl.SizeCache
}

func (x *OperatorSetIdProto) Reset() {
	*x = OperatorSetIdProto{}
	mi := &file_onnx_proto_msgTypes[18]
	ms := protoimpl.X.MessageStateOf(protoimpl.Pointer(x))
	ms.StoreMessageInfo(mi)
}

func (x *OperatorSetIdProto) String() string {
	return protoimpl.X.MessageStringOf(x)
}

func (*OperatorSetIdProto) ProtoMessage() {}

func (x *OperatorSetIdProto) ProtoReflect() protoreflect.Message {
	mi := &file_onnx_proto_msgTypes[18]
	if x != nil {
		ms := protoimpl.X.MessageStateOf(protoimpl.Pointer(x))
		if ms.LoadMessageInfo() == nil {
			ms.StoreMessageInfo(mi)
		}
		return ms
	}
	return mi.MessageOf(x)
}

func (*OperatorSetIdProto) Descriptor() ([]byte, []int) {
	return file_onnx_proto_rawDescGZIP(), []int{18}
}

func (x *OperatorSetIdProto) GetDomain() string {
	if x != nil && x.Domain != nil {
		return *x.Domain
	}
	return ""
}

func (x *OperatorSetIdProto) GetVersion() int64 {
	if x != nil && x.Version != nil {
		return *x.Version
	}
	return 0
}

type FunctionProto struct {
	state          protoimpl.MessageState    `protogen:"open.v1"`
	Name           *string                   `protobuf:"bytes,1,opt,name=name" json:"name,omitempty"`
	Input          []string                  `protobuf:"bytes,4,rep,name=input" json:"input,omitempty"`
	Output         []string                  `protobuf:"bytes,5,rep,name=output" json:"output,omitempty"`
	Attribute      []string                  `protobuf:"bytes,6,rep,name=attribute" json:"attribute,omitempty"`
	AttributeProto []*AttributeProto         `protobuf:"bytes,11,rep,name=attribute_proto,json=attributeProto" json:"attribute_proto,omitempty"`
	Node           []*NodeProto              `protobuf:"bytes,7,rep,name=node" json:"node,omitempty"`
	DocString      *string                   `protobuf:"bytes,8,opt,name=doc_string,json=docString" json:"doc_string,omitempty"`
	OpsetImport    []*OperatorSetIdProto     `protobuf:"bytes,9,rep,name=opset_import,json=opsetImport" json:"opset_import,omitempty"`
	Domain         *string                   `protobuf:"bytes,10,opt,name=domain" json:"domain,omitempty"`
	Overload       *string                   `protobuf:"bytes,13,opt,name=overload" json:"overload,omitempty"`
	ValueInfo      []*ValueInfoProto         `protobuf:"bytes,12,rep,name=value_info,json=valueInfo" json:"value_info,omitempty"`
	MetadataProps  []*StringStringEntryProto `protobuf:"bytes,14,rep,name=metadata_props,json=metadataProps" json:"metadata_props,omitempty"`
	unknownFields  protoimpl.UnknownFields
	sizeCache      protoimpl.SizeCache
}

func (x *FunctionProto) Reset() {
	*x = FunctionProto{}
	mi := &file_onnx_proto_msgTypes[19]
	ms := protoimpl.X.MessageStateOf(protoimpl.Pointer(x))
	ms.StoreMessageInfo(mi)
}

func (x *FunctionProto) String() string {
	return protoimpl.X.MessageStringOf(x)
}

func (*FunctionProto) ProtoMessage() {}

func (x *FunctionProto) ProtoReflect() protoreflect.Message {
	mi := &file_onnx_proto_msgTypes[19]
	if x != nil {
		ms := protoimpl.X.MessageStateOf(protoimpl.Pointer(x))
		if ms.LoadMessageInfo() == nil {
			ms.StoreMessageInfo(mi)
		}
		return ms
	}
	return mi.MessageOf(x)
}

func (*FunctionProto) Descriptor() ([]byte, []int) {
	return file_onnx_proto_rawDescGZIP(), []int{19}
}

func (x *FunctionProto) GetName() string {
	if x != nil && x.Name != nil {
		return *x.Name
	}
	return ""
}

func (x *FunctionProto) GetInput() []string {
	if x != nil {
		return x.Input
	}
	return nil
}

func (x *FunctionProto) GetOutput() []string {
	if x != nil {
		return x.Output
	}
	return nil
}

func (x *FunctionProto) GetAttribute() []string {
	if x != nil {
		return x.Attribute
	}
	return nil
}

func (x *FunctionProto) GetAttributeProto() []*AttributeProto {
	if x != nil {
		return x.AttributeProto
	}
	return nil
}

func (x *FunctionProto) GetNode() []*NodeProto {
	if x != nil {
		return x.Node
	}
	return nil
}

func (x *FunctionProto) GetDocString() string {
	if x != nil && x.DocString != nil {
		return *x.DocString
	}
	return ""
}

func (x *FunctionProto) GetOpsetImport() []*OperatorSetIdProto {
	if x != nil {
		return x.OpsetImport
	}
	return nil
}

func (x *FunctionProto) GetDomain() string {
	if x != nil && x.Domain != nil {
		return *x.Domain
	}
	return ""
}

func (x *FunctionProto) GetOverload() string {
	if x != nil && x.Overload != nil {
		return *x.Overload
	}
	return ""
}

func (x *FunctionProto) GetValueInfo() []*ValueInfoProto {
	if x != nil {
		return x.ValueInfo
	}
	return nil
}

func (x *FunctionProto) GetMetadataProps() []*StringStringEntryProto {
	if x != nil {
		return x.MetadataProps
	}
	return nil
}

type TensorProto_Segment struct {
	state         protoimpl.MessageState `protogen:"open.v1"`
	Begin         *int64                 `protobuf:"varint,1,opt,name=begin" json:"begin,omitempty"`
	End           *int64                 `protobuf:"varint,2,opt,name=end" json:"end,omitempty"`
	unknownFields protoimpl.UnknownFields
	sizeCache     protoimpl.SizeCache
}

func (x *TensorProto_Segment) Reset() {
	*x = TensorProto_Segment{}
	mi := &file_onnx_proto_msgTypes[20]
	ms := protoimpl.X.MessageStateOf(protoimpl.Pointer(x))
	ms.StoreMessageInfo(mi)
}

func (x *TensorProto_Segment) String() string {
	return protoimpl.X.MessageStringOf(x)
}

func (*TensorProto_Segment) ProtoMessage() {}

func (x *TensorProto_Segment) ProtoReflect() protoreflect.Message {
	mi := &file_onnx_proto_msgTypes[20]
	if x != nil {
		ms := protoimpl.X.MessageStateOf(protoimpl.Pointer(x))
		if ms.LoadMessageInfo() == nil {
			ms.StoreMessageInfo(mi)
		}
		return ms
	}
	return mi.MessageOf(x)
}

func (*TensorProto_Segment) Descriptor() ([]byte, []int) {
	return file_onnx_proto_rawDescGZIP(), []int{14, 0}
}

func (x *TensorProto_Segment) GetBegin() int64 {
	if x != nil && x.Begin != nil {
		return *x.Begin
	}
	return 0
}

func (x *TensorProto_Segment) GetEnd() int64 {
	if x != nil && x.End != nil {
		return *x.End
	}
	return 0
}

type TensorShapeProto_Dimension struct {
	state protoimpl.MessageState `protogen:"open.v1"`
	Value         isTensorShapeProto_Dimension_Value `protobuf_oneof:"value"`
	Denotation    *string                            `protobuf:"bytes,3,opt,name=denotation" json:"denotation,omitempty"`
	unknownFields protoimpl.UnknownFields
	sizeCache     protoimpl.SizeCache
}

func (x *TensorShapeProto_Dimension) Reset() {
	*x = TensorShapeProto_Dimension{}
	mi := &file_onnx_proto_msgTypes[21]
	ms := protoimpl.X.MessageStateOf(protoimpl.Pointer(x))
	ms.StoreMessageInfo(mi)
}

func (x *TensorShapeProto_Dimension) String() string {
	return protoimpl.X.MessageStringOf(x)
}

func (*TensorShapeProto_Dimension) ProtoMessage() {}

func (x *TensorShapeProto_Dimension) ProtoReflect() protoreflect.Message {
	mi := &file_onnx_proto_msgTypes[21]
	if x != nil {
		ms := protoimpl.X.MessageStateOf(protoimpl.Pointer(x))
		if ms.LoadMessageInfo() == nil {
			ms.StoreMessageInfo(mi)
		}
		return ms
	}
	return mi.MessageOf(x)
}

func (*TensorShapeProto_Dimension) Descriptor() ([]byte, []int) {
	return file_onnx_proto_rawDescGZIP(), []int{16, 0}
}

func (x *TensorShapeProto_Dimension) GetValue() isTensorShapeProto_Dimension_Value {
	if x != nil {
		return x.Value
	}
	return nil
}

func (x *TensorShapeProto_Dimension) GetDimValue() int64 {
	if x != nil {
		if x, ok := x.Value.(*TensorShapeProto_Dimension_DimValue); ok {
			return x.DimValue
		}
	}
	return 0
}

func (x *TensorShapeProto_Dimension) GetDimParam() string {
	if x != nil {
		if x, ok := x.Value.(*TensorShapeProto_Dimension_DimParam); ok {
			return x.DimParam
		}
	}
	return ""
}

func (x *TensorShapeProto_Dimension) GetDenotation() string {
	if x != nil && x.Denotation != nil {
		return *x.Denotation
	}
	return ""
}

type isTensorShapeProto_Dimension_Value interface {
	isTensorShapeProto_Dimension_Value()
}

type TensorShapeProto_Dimension_DimValue struct {
	DimValue int64 `protobuf:"varint,1,opt,name=dim_value,json=dimValue,oneof"`
}

type TensorShapeProto_Dimension_DimParam struct {
	DimParam string `protobuf:"bytes,2,opt,name=dim_param,json=dimParam,oneof"`
}

func (*TensorShapeProto_Dimension_DimValue) isTensorShapeProto_Dimension_Value() {}

func (*TensorShapeProto_Dimension_DimParam) isTensorShapeProto_Dimension_Value() {}

type TypeProto_Tensor struct {
	state         protoimpl.MessageState `protogen:"open.v1"`
	ElemType      *int32                 `protobuf:"varint,1,opt,name=elem_type,json=elemType" json:"elem_type,omitempty"`
	Shape         *TensorShapeProto      `protobuf:"bytes,2,opt,name=shape" json:"shape,omitempty"`
	unknownFields protoimpl.UnknownFields
	sizeCache     protoimpl.SizeCache
}

func (x *TypeProto_Tensor) Reset() {
	*x = TypeProto_Tensor{}
	mi := &file_onnx_proto_msgTypes[22]
	ms := protoimpl.X.MessageStateOf(protoimpl.Pointer(x))
	ms.StoreMessageInfo(mi)
}

func (x *TypeProto_Tensor) String() string {
	return protoimpl.X.MessageStringOf(x)
}

func (*TypeProto_Tensor) ProtoMessage() {}

func (x *TypeProto_Tensor) ProtoReflect() protoreflect.Message {
	mi := &file_onnx_proto_msgTypes[22]
	if x != nil {
		ms := protoimpl.X.MessageStateOf(protoimpl.Pointer(x))
		if ms.LoadMessageInfo() == nil {
			ms.StoreMessageInfo(mi)
		}
		return ms
	}
	return mi.MessageOf(x)
}

func (*TypeProto_Tensor) Descriptor() ([]byte, []int) {
	return file_onnx_proto_rawDescGZIP(), []int{17, 0}
}

func (x *TypeProto_Tensor) GetElemType() int32 {
	if x != nil && x.ElemType != nil {
		return *x.ElemType
	}
	return 0
}

func (x *TypeProto_Tensor) GetShape() *TensorShapeProto {
	if x != nil {
		return x.Shape
	}
	return nil
}

type TypeProto_Sequence struct {
	state         protoimpl.MessageState `protogen:"open.v1"`
	ElemType      *TypeProto             `protobuf:"bytes,1,opt,name=elem_type,json=elemType" json:"elem_type,omitempty"`
	unknownFields protoimpl.UnknownFields
	sizeCache     protoimpl.SizeCache
}

func (x *TypeProto_Sequence) Reset() {
	*x = TypeProto_Sequence{}
	mi := &file_onnx_proto_msgTypes[23]
	ms := protoimpl.X.MessageStateOf(protoimpl.Pointer(x))
	ms.StoreMessageInfo(mi)
}

func (x *TypeProto_Sequence) String() string {
	return protoimpl.X.MessageStringOf(x)
}

func (*TypeProto_Sequence) ProtoMessage() {}

func (x *TypeProto_Sequence) ProtoReflect() protoreflect.Message {
	mi := &file_onnx_proto_msgTypes[23]
	if x != nil {
		ms := protoimpl.X.MessageStateOf(protoimpl.Pointer(x))
		if ms.LoadMessageInfo() == nil {
			ms.StoreMessageInfo(mi)
		}
		return ms
	}
	return mi.MessageOf(x)
}

func (*TypeProto_Sequence) Descriptor() ([]byte, []int) {
	return file_onnx_proto_rawDescGZIP(), []int{17, 1}
}

func (x *TypeProto_Sequence) GetElemType() *TypeProto {
	if x != nil {
		return x.ElemType
	}
	return nil
}

type TypeProto_Map struct {
	state         protoimpl.MessageState `protogen:"open.v1"`
	KeyType       *int32                 `protobuf:"varint,1,opt,name=key_type,json=keyType" json:"key_type,omitempty"`
	ValueType     *TypeProto             `protobuf:"bytes,2,opt,name=value_type,json=valueType" json:"value_type,omitempty"`
	unknownFields protoimpl.UnknownFields
	sizeCache     protoimpl.SizeCache
}

func (x *TypeProto_Map) Reset() {
	*x = TypeProto_Map{}
	mi := &file_onnx_proto_msgTypes[24]
	ms := protoimpl.X.MessageStateOf(protoimpl.Pointer(x))
	ms.StoreMessageInfo(mi)
}

func (x *TypeProto_Map) String() string {
	return protoimpl.X.MessageStringOf(x)
}

func (*TypeProto_Map) ProtoMessage() {}

func (x *TypeProto_Map) ProtoReflect() protoreflect.Message {
	mi := &file_onnx_proto_msgTypes[24]
	if x != nil {
		ms := protoimpl.X.MessageStateOf(protoimpl.Pointer(x))
		if ms.LoadMessageInfo() == nil {
			ms.StoreMessageInfo(mi)
		}
		return ms
	}
	return mi.MessageOf(x)
}

func (*TypeProto_Map) Descriptor() ([]byte, []int) {
	return file_onnx_proto_rawDescGZIP(), []int{17, 2}
}

func (x *TypeProto_Map) GetKeyType() int32 {
	if x != nil && x.KeyType != nil {
		return *x.KeyType
	}
	return 0
}

func (x *TypeProto_Map) GetValueType() *TypeProto {
	if x != nil {
		return x.ValueType
	}
	return nil
}

type TypeProto_Optional struct {
	state         protoimpl.MessageState `protogen:"open.v1"`
	ElemType      *TypeProto             `protobuf:"bytes,1,opt,name=elem_type,json=elemType" json:"elem_type,omitempty"`
	unknownFields protoimpl.UnknownFields
	sizeCache     protoimpl.SizeCache
}

func (x *TypeProto_Optional) Reset() {
	*x = TypeProto_Optional{}
	mi := &file_onnx_proto_msgTypes[25]
	ms := protoimpl.X.MessageStateOf(protoimpl.Pointer(x))
	ms.StoreMessageInfo(mi)
}

func (x *TypeProto_Optional) String() string {
	return protoimpl.X.MessageStringOf(x)
}

func (*TypeProto_Optional) ProtoMessage() {}

func (x *TypeProto_Optional) ProtoReflect() protoreflect.Message {
	mi := &file_onnx_proto_msgTypes[25]
	if x != nil {
		ms := protoimpl.X.MessageStateOf(protoimpl.Pointer(x))
		if ms.LoadMessageInfo() == nil {
			ms.StoreMessageInfo(mi)
		}
		return ms
	}
	return mi.MessageOf(x)
}

func (*TypeProto_Optional) Descriptor() ([]byte, []int) {
	return file_onnx_proto_rawDescGZIP(), []int{17, 3}
}

func (x *TypeProto_Optional) GetElemType() *TypeProto {
	if x != nil {
		return x.ElemType
	}
	return nil
}

type TypeProto_SparseTensor struct {
	state         protoimpl.MessageState `protogen:"open.v1"`
	ElemType      *int32                 `protobuf:"varint,1,opt,name=elem_type,json=elemType" json:"elem_type,omitempty"`
	Shape         *TensorShapeProto      `protobuf:"bytes,2,opt,name=shape" json:"shape,omitempty"`
	unknownFields protoimpl.UnknownFields
	sizeCache     protoimpl.SizeCache
}

func (x *TypeProto_SparseTensor) Reset() {
	*x = TypeProto_SparseTensor{}
	mi := &file_onnx_proto_msgTypes[26]
	ms := protoimpl.X.MessageStateOf(protoimpl.Pointer(x))
	ms.StoreMessageInfo(mi)
}

func (x *TypeProto_SparseTensor) String() string {
	return protoimpl.X.MessageStringOf(x)
}

func (*TypeProto_SparseTensor) ProtoMessage() {}

func (x *TypeProto_SparseTensor) ProtoReflect() protoreflect.Message {
	mi := &file_onnx_proto_msgTypes[26]
	if x != nil {
		ms := protoimpl.X.MessageStateOf(protoimpl.Pointer(x))
		if ms.LoadMessageInfo() == nil {
			ms.StoreMessageInfo(mi)
		}
		return ms
	}
	return mi.MessageOf(x)
}

func (*TypeProto_SparseTensor) Descriptor() ([]byte, []int) {
	return file_onnx_proto_rawDescGZIP(), []int{17, 4}
}

func (x *TypeProto_SparseTensor) GetElemType() int32 {
	if x != nil && x.ElemType != nil {
		return *x.ElemType
	}
	return 0
}

func (x *TypeProto_SparseTensor) GetShape() *TensorShapeProto {
	if x != nil {
		return x.Shape
	}
	return nil
}

var File_onnx_proto protoreflect.FileDescriptor

const file_onnx_proto_rawDesc = "" +
	"\n" +
	"\n" +
	"onnx.proto\x12\x04onnx\"\xe3\x06\n" +
	"\x0eAttributeProto\x12\x12\n" +
	"\x04name\x18\x01 \x01(\tR\x04name\x12\"\n" +
	"\rref_attr_name\x18\x15 \x01(\tR\vrefAttrName\x12\x1d\n" +
	"\n" +
	"doc_string\x18\r \x01(\tR\tdocString\x126\n" +
	"\x04type\x18\x14 \x01(\x0e2\".onnx.AttributeProto.AttributeTypeR\x04type\x12\f\n" +
	"\x01f\x18\x02 \x01(\x02R\x01f\x12\f\n" +
	"\x01i\x18\x03 \x01(\x03R\x01i\x12\f\n" +
	"\x01s\x18\x04 \x01(\fR\x01s\x12\x1f\n" +
	"\x01t\x18\x05 \x01(\v2\x11.onnx.TensorProtoR\x01t\x12\x1e\n" +
	"\x01g\x18\x06 \x01(\v2\x10.onnx.GraphProtoR\x01g\x12<\n" +
	"\rsparse_tensor\x18\x16 \x01(\v2\x17.onnx.SparseTensorProtoR\fsparseTensor\x12\x1f\n" +
	"\x02tp\x18\x0e \x01(\v2\x0f.onnx.TypeProtoR\x02tp\x12\x16\n" +
	"\x06floats\x18\a \x03(\x02R\x06floats\x12\x12\n" +
	"\x04ints\x18\b \x03(\x03R\x04ints\x12\x18\n" +
	"\astrings\x18\t \x03(\fR\astrings\x12+\n" +
	"\atensors\x18\n" +
	" \x03(\v2\x11.onnx.TensorProtoR\atensors\x12(\n" +
	"\x06graphs\x18\v \x03(\v2\x10.onnx.GraphProtoR\x06graphs\x12>\n" +
	"\x0esparse_tensors\x18\x17 \x03(\v2\x17.onnx.SparseTensorProtoR\rsparseTensors\x120\n" +
	"\vtype_protos\x18\x0f \x03(\v2\x0f.onnx.TypeProtoR\n" +
	"typeProtos\"\xd9\x01\n" +
	"\rAttributeType\x12\r\n" +
	"\tUNDEFINED\x10\x00\x12\t\n" +
	"\x05FLOAT\x10\x01\x12\a\n" +
	"\x03INT\x10\x02\x12\n" +
	"\n" +
	"\x06STRING\x10\x03\x12\n" +
	"\n" +
	"\x06TENSOR\x10\x04\x12\t\n" +
	"\x05GRAPH\x10\x05\x12\x11\n" +
	"\rSPARSE_TENSOR\x10\v\x12\x0e\n" +
	"\n" +
	"TYPE_PROTO\x10\r\x12\n" +
	"\n" +
	"\x06FLOATS\x10\x06\x12\b\n" +
	"\x04INTS\x10\a\x12\v\n" +
	"\aSTRINGS\x10\b\x12\v\n" +
	"\aTENSORS\x10\t\x12\n" +
	"\n" +
	"\x06GRAPHS\x10\n" +
	"\x12\x12\n" +
	"\x0eSPARSE_TENSORS\x10\f\x12\x0f\n" +
	"\vTYPE_PROTOS\x10\x0eJ\x04\b\f\x10\rJ\x04\b\x10\x10\x14R\x01v\"\xad\x01\n" +
	"\x0eValueInfoProto\x12\x12\n" +
	"\x04name\x18\x01 \x01(\tR\x04name\x12#\n" +
	"\x04type\x18\x02 \x01(\v2\x0f.onnx.TypeProtoR\x04type\x12\x1d\n" +
	"\n" +
	"doc_string\x18\x03 \x01(\tR\tdocString\x12C\n" +
	"\x0emetadata_props\x18\x04 \x03(\v2\x1c.onnx.StringStringEntryProtoR\rmetadataProps\"\x8b\x03\n" +
	"\tNodeProto\x12\x14\n" +
	"\x05input\x18\x01 \x03(\tR\x05input\x12\x16\n" +
	"\x06output\x18\x02 \x03(\tR\x06output\x12\x12\n" +
	"\x04name\x18\x03 \x01(\tR\x04name\x12\x17\n" +
	"\aop_type\x18\x04 \x01(\tR\x06opType\x12\x16\n" +
	"\x06domain\x18\a \x01(\tR\x06domain\x12\x1a\n" +
	"\boverload\x18\b \x01(\tR\boverload\x122\n" +
	"\tattribute\x18\x05 \x03(\v2\x14.onnx.AttributeProtoR\tattribute\x12\x1d\n" +
	"\n" +
	"doc_string\x18\x06 \x01(\tR\tdocString\x12C\n" +
	"\x0emetadata_props\x18\t \x03(\v2\x1c.onnx.StringStringEntryProtoR\rmetadataProps\x12W\n" +
	"\x15device_configurations\x18\n" +
	" \x03(\v2\".onnx.NodeDeviceConfigurationProtoR\x14deviceConfigurations\">\n" +
	"\x14IntIntListEntryProto\x12\x10\n" +
	"\x03key\x18\x01 \x01(\x03R\x03key\x12\x14\n" +
	"\x05value\x18\x02 \x03(\x03R\x05value\"\xae\x01\n" +
	"\x1cNodeDeviceConfigurationProto\x12)\n" +
	"\x10configuration_id\x18\x01 \x01(\tR\x0fconfigurationId\x12<\n" +
	"\rsharding_spec\x18\x02 \x03(\v2\x17.onnx.ShardingSpecProtoR\fshardingSpec\x12%\n" +
	"\x0epipeline_stage\x18\x03 \x01(\x05R\rpipelineStage\"\xda\x01\n" +
	"\x11ShardingSpecProto\x12\x1f\n" +
	"\vtensor_name\x18\x01 \x01(\tR\n" +
	"tensorName\x12\x16\n" +
	"\x06device\x18\x02 \x03(\x03R\x06device\x12T\n" +
	"\x19index_to_device_group_map\x18\x03 \x03(\v2\x1a.onnx.IntIntListEntryProtoR\x15indexToDeviceGroupMap\x126\n" +
	"\vsharded_dim\x18\x04 \x03(\v2\x15.onnx.ShardedDimProtoR\n" +
	"shardedDim\"k\n" +
	"\x0fShardedDimProto\x12\x12\n" +
	"\x04axis\x18\x01 \x01(\x03R\x04axis\x12D\n" +
	"\x0fsimple_sharding\x18\x02 \x03(\v2\x1b.onnx.SimpleShardedDimProtoR\x0esimpleSharding\"{\n" +
	"\x15SimpleShardedDimProto\x12\x1d\n" +
	"\tdim_value\x18\x01 \x01(\x03H\x00R\bdimValue\x12\x1d\n" +
	"\tdim_param\x18\x02 \x01(\tH\x00R\bdimParam\x12\x1d\n" +
	"\n" +
	"num_shards\x18\x03 \x01(\x03R\tnumShardsB\x05\n" +
	"\x03dim\"\x97\x02\n" +
	"\x11TrainingInfoProto\x128\n" +
	"\x0einitialization\x18\x01 \x01(\v2\x10.onnx.GraphProtoR\x0einitialization\x12.\n" +
	"\talgorithm\x18\x02 \x01(\v2\x10.onnx.GraphProtoR\talgorithm\x12S\n" +
	"\x16initialization_binding\x18\x03 \x03(\v2\x1c.onnx.StringStringEntryProtoR\x15initializationBinding\x12C\n" +
	"\x0eupdate_binding\x18\x04 \x03(\v2\x1c.onnx.StringStringEntryProtoR\rupdateBinding\"\xb8\x04\n" +
	"\n" +
	"ModelProto\x12\x1d\n" +
	"\n" +
	"ir_version\x18\x01 \x01(\x03R\tirVersion\x12;\n" +
	"\fopset_import\x18\b \x03(\v2\x18.onnx.OperatorSetIdProtoR\vopsetImport\x12#\n" +
	"\rproducer_name\x18\x02 \x01(\tR\fproducerName\x12)\n" +
	"\x10producer_version\x18\x03 \x01(\tR\x0fproducerVersion\x12\x16\n" +
	"\x06domain\x18\x04 \x01(\tR\x06domain\x12#\n" +
	"\rmodel_version\x18\x05 \x01(\x03R\fmodelVersion\x12\x1d\n" +
	"\n" +
	"doc_string\x18\x06 \x01(\tR\tdocString\x12&\n" +
	"\x05graph\x18\a \x01(\v2\x10.onnx.GraphProtoR\x05graph\x12C\n" +
	"\x0emetadata_props\x18\x0e \x03(\v2\x1c.onnx.StringStringEntryProtoR\rmetadataProps\x12<\n" +
	"\rtraining_info\x18\x14 \x03(\v2\x17.onnx.TrainingInfoProtoR\ftrainingInfo\x121\n" +
	"\tfunctions\x18\x19 \x03(\v2\x13.onnx.FunctionProtoR\tfunctions\x12D\n" +
	"\rconfiguration\x18\x1a \x03(\v2\x1e.onnx.DeviceConfigurationProtoR\rconfiguration\"g\n" +
	"\x18DeviceConfigurationProto\x12\x12\n" +
	"\x04name\x18\x01 \x01(\tR\x04name\x12\x1f\n" +
	"\vnum_devices\x18\x02 \x01(\x05R\n" +
	"numDevices\x12\x16\n" +
	"\x06device\x18\x03 \x03(\tR\x06device\"@\n" +
	"\x16StringStringEntryProto\x12\x10\n" +
	"\x03key\x18\x01 \x01(\tR\x03key\x12\x14\n" +
	"\x05value\x18\x02 \x01(\tR\x05value\"\x92\x01\n" +
	"\x10TensorAnnotation\x12\x1f\n" +
	"\vtensor_name\x18\x01 \x01(\tR\n" +
	"tensorName\x12]\n" +
	"\x1cquant_parameter_tensor_names\x18\x02 \x03(\v2\x1c.onnx.StringStringEntryProtoR\x19quantParameterTensorNames\"\xcc\x04\n" +
	"\n" +
	"GraphProto\x12#\n" +
	"\x04node\x18\x01 \x03(\v2\x0f.onnx.NodeProtoR\x04node\x12\x12\n" +
	"\x04name\x18\x02 \x01(\tR\x04name\x123\n" +
	"\vinitializer\x18\x05 \x03(\v2\x11.onnx.TensorProtoR\vinitializer\x12F\n" +
	"\x12sparse_initializer\x18\x0f \x03(\v2\x17.onnx.SparseTensorProtoR\x11sparseInitializer\x12\x1d\n" +
	"\n" +
	"doc_string\x18\n" +
	" \x01(\tR\tdocString\x12*\n" +
	"\x05input\x18\v \x03(\v2\x14.onnx.ValueInfoProtoR\x05input\x12,\n" +
	"\x06output\x18\f \x03(\v2\x14.onnx.ValueInfoProtoR\x06output\x123\n" +
	"\n" +
	"value_info\x18\r \x03(\v2\x14.onnx.ValueInfoProtoR\tvalueInfo\x12O\n" +
	"\x17quantization_annotation\x18\x0e \x03(\v2\x16.onnx.TensorAnnotationR\x16quantizationAnnotation\x12C\n" +
	"\x0emetadata_props\x18\x10 \x03(\v2\x1c.onnx.StringStringEntryProtoR\rmetadataPropsJ\x04\b\x03\x10\x04J\x04\b\x04\x10\x05J\x04\b\x06\x10\n" +
	"R\n" +
	"ir_versionR\x10producer_versionR\fproducer_tagR\x06domain\"\xb1\b\n" +
	"\vTensorProto\x12\x12\n" +
	"\x04dims\x18\x01 \x03(\x03R\x04dims\x12\x1b\n" +
	"\tdata_type\x18\x02 \x01(\x05R\bdataType\x123\n" +
	"\asegment\x18\x03 \x01(\v2\x19.onnx.TensorProto.SegmentR\asegment\x12!\n" +
	"\n" +
	"float_data\x18\x04 \x03(\x02B\x02\x10\x01R\tfloatData\x12!\n" +
	"\n" +
	"int32_data\x18\x05 \x03(\x05B\x02\x10\x01R\tint32Data\x12\x1f\n" +
	"\vstring_data\x18\x06 \x03(\fR\n" +
	"stringData\x12!\n" +
	"\n" +
	"int64_data\x18\a \x03(\x03B\x02\x10\x01R\tint64Data\x12\x12\n" +
	"\x04name\x18\b \x01(\tR\x04name\x12\x1d\n" +
	"\n" +
	"doc_string\x18\f \x01(\tR\tdocString\x12\x19\n" +
	"\braw_data\x18\t \x01(\fR\arawData\x12A\n" +
	"\rexternal_data\x18\r \x03(\v2\x1c.onnx.StringStringEntryProtoR\fexternalData\x12C\n" +
	"\rdata_location\x18\x0e \x01(\x0e2\x1e.onnx.TensorProto.DataLocationR\fdataLocation\x12#\n" +
	"\vdouble_data\x18\n" +
	" \x03(\x01B\x02\x10\x01R\n" +
	"doubleData\x12#\n" +
	"\vuint64_data\x18\v \x03(\x04B\x02\x10\x01R\n" +
	"uint64Data\x12C\n" +
	"\x0emetadata_props\x18\x10 \x03(\v2\x1c.onnx.StringStringEntryProtoR\rmetadataProps\x1a1\n" +
	"\aSegment\x12\x14\n" +
	"\x05begin\x18\x01 \x01(\x03R\x05begin\x12\x10\n" +
	"\x03end\x18\x02 \x01(\x03R\x03end\"\xee\x02\n" +
	"\bDataType\x12\r\n" +
	"\tUNDEFINED\x10\x00\x12\t\n" +
	"\x05FLOAT\x10\x01\x12\t\n" +
	"\x05UINT8\x10\x02\x12\b\n" +
	"\x04INT8\x10\x03\x12\n" +
	"\n" +
	"\x06UINT16\x10\x04\x12\t\n" +
	"\x05INT16\x10\x05\x12\t\n" +
	"\x05INT32\x10\x06\x12\t\n" +
	"\x05INT64\x10\a\x12\n" +
	"\n" +
	"\x06STRING\x10\b\x12\b\n" +
	"\x04BOOL\x10\t\x12\v\n" +
	"\aFLOAT16\x10\n" +
	"\x12\n" +
	"\n" +
	"\x06DOUBLE\x10\v\x12\n" +
	"\n" +
	"\x06UINT32\x10\f\x12\n" +
	"\n" +
	"\x06UINT64\x10\r\x12\r\n" +
	"\tCOMPLEX64\x10\x0e\x12\x0e\n" +
	"\n" +
	"COMPLEX128\x10\x0f\x12\f\n" +
	"\bBFLOAT16\x10\x10\x12\x10\n" +
	"\fFLOAT8E4M3FN\x10\x11\x12\x12\n" +
	"\x0eFLOAT8E4M3FNUZ\x10\x12\x12\x0e\n" +
	"\n" +
	"FLOAT8E5M2\x10\x13\x12\x12\n" +
	"\x0eFLOAT8E5M2FNUZ\x10\x14\x12\t\n" +
	"\x05UINT4\x10\x15\x12\b\n" +
	"\x04INT4\x10\x16\x12\x0e\n" +
	"\n" +
	"FLOAT4E2M1\x10\x17\x12\x0e\n" +
	"\n" +
	"FLOAT8E8M0\x10\x18\x12\t\n" +
	"\x05UINT2\x10\x19\x12\b\n" +
	"\x04INT2\x10\x1a\")\n" +
	"\fDataLocation\x12\v\n" +
	"\aDEFAULT\x10\x00\x12\f\n" +
	"\bEXTERNAL\x10\x01\"\x7f\n" +
	"\x11SparseTensorProto\x12)\n" +
	"\x06values\x18\x01 \x01(\v2\x11.onnx.TensorProtoR\x06values\x12+\n" +
	"\aindices\x18\x02 \x01(\v2\x11.onnx.TensorProtoR\aindices\x12\x12\n" +
	"\x04dims\x18\x03 \x03(\x03R\x04dims\"\xba\x01\n" +
	"\x10TensorShapeProto\x122\n" +
	"\x03dim\x18\x01 \x03(\v2 .onnx.TensorShapeProto.DimensionR\x03dim\x1ar\n" +
	"\tDimension\x12\x1d\n" +
	"\tdim_value\x18\x01 \x01(\x03H\x00R\bdimValue\x12\x1d\n" +
	"\tdim_param\x18\x02 \x01(\tH\x00R\bdimParam\x12\x1e\n" +
	"\n" +
	"denotation\x18\x03 \x01(\tR\n" +
	"denotationB\a\n" +
	"\x05value\"\xe7\x05\n" +
	"\tTypeProto\x129\n" +
	"\vtensor_type\x18\x01 \x01(\v2\x16.onnx.TypeProto.TensorH\x00R\n" +
	"tensorType\x12?\n" +
	"\rsequence_type\x18\x04 \x01(\v2\x18.onnx.TypeProto.SequenceH\x00R\fsequenceType\x120\n" +
	"\bmap_type\x18\x05 \x01(\v2\x13.onnx.TypeProto.MapH\x00R\amapType\x12?\n" +
	"\roptional_type\x18\t \x01(\v2\x18.onnx.TypeProto.OptionalH\x00R\foptionalType\x12L\n" +
	"\x12sparse_tensor_type\x18\b \x01(\v2\x1c.onnx.TypeProto.SparseTensorH\x00R\x10sparseTensorType\x12\x1e\n" +
	"\n" +
	"denotation\x18\x06 \x01(\tR\n" +
	"denotation\x1aS\n" +
	"\x06Tensor\x12\x1b\n" +
	"\telem_type\x18\x01 \x01(\x05R\belemType\x12,\n" +
	"\x05shape\x18\x02 \x01(\v2\x16.onnx.TensorShapeProtoR\x05shape\x1a8\n" +
	"\bSequence\x12,\n" +
	"\telem_type\x18\x01 \x01(\v2\x0f.onnx.TypeProtoR\belemType\x1aP\n" +
	"\x03Map\x12\x19\n" +
	"\bkey_type\x18\x01 \x01(\x05R\akeyType\x12.\n" +
	"\n" +
	"value_type\x18\x02 \x01(\v2\x0f.onnx.TypeProtoR\tvalueType\x1a8\n" +
	"\bOptional\x12,\n" +
	"\telem_type\x18\x01 \x01(\v2\x0f.onnx.TypeProtoR\belemType\x1aY\n" +
	"\fSparseTensor\x12\x1b\n" +
	"\telem_type\x18\x01 \x01(\x05R\belemType\x12,\n" +
	"\x05shape\x18\x02 \x01(\v2\x16.onnx.TensorShapeProtoR\x05shapeB\a\n" +
	"\x05value\"F\n" +
	"\x12OperatorSetIdProto\x12\x16\n" +
	"\x06domain\x18\x01 \x01(\tR\x06domain\x12\x18\n" +
	"\aversion\x18\x02 \x01(\x03R\aversion\"\x80\x04\n" +
	"\rFunctionProto\x12\x12\n" +
	"\x04name\x18\x01 \x01(\tR\x04name\x12\x14\n" +
	"\x05input\x18\x04 \x03(\tR\x05input\x12\x16\n" +
	"\x06output\x18\x05 \x03(\tR\x06output\x12\x1c\n" +
	"\tattribute\x18\x06 \x03(\tR\tattribute\x12=\n" +
	"\x0fattribute_proto\x18\v \x03(\v2\x14.onnx.AttributeProtoR\x0eattributeProto\x12#\n" +
	"\x04node\x18\a \x03(\v2\x0f.onnx.NodeProtoR\x04node\x12\x1d\n" +
	"\n" +
	"doc_string\x18\b \x01(\tR\tdocString\x12;\n" +
	"\fopset_import\x18\t \x03(\v2\x18.onnx.OperatorSetIdProtoR\vopsetImport\x12\x16\n" +
	"\x06domain\x18\n" +
	" \x01(\tR\x06domain\x12\x1a\n" +
	"\boverload\x18\r \x01(\tR\boverload\x123\n" +
	"\n" +
	"value_info\x18\f \x03(\v2\x14.onnx.ValueInfoProtoR\tvalueInfo\x12C\n" +
	"\x0emetadata_props\x18\x0e \x03(\v2\x1c.onnx.StringStringEntryProtoR\rmetadataPropsJ\x04\b\x02\x10\x03J\x04\b\x03\x10\x04R\rsince_versionR\x06status*\xd3\x02\n" +
	"\aVersion\x12\x19\n" +
	"\x15IR_VERSION_2017_10_10\x10\x01\x12\x19\n" +
	"\x15IR_VERSION_2017_10_30\x10\x02\x12\x18\n" +
	"\x14IR_VERSION_2017_11_3\x10\x03\x12\x18\n" +
	"\x14IR_VERSION_2019_1_22\x10\x04\x12\x18\n" +
	"\x14IR_VERSION_2019_3_18\x10\x05\x12\x18\n" +
	"\x14IR_VERSION_2019_9_19\x10\x06\x12\x17\n" +
	"\x13IR_VERSION_2020_5_8\x10\a\x12\x18\n" +
	"\x14IR_VERSION_2021_7_30\x10\b\x12\x17\n" +
	"\x13IR_VERSION_2023_5_5\x10\t\x12\x18\n" +
	"\x14IR_VERSION_2024_3_25\x10\n" +
	"\x12\x19\n" +
	"\x15IR_VERSION_2025_05_12\x10\v\x12\x19\n" +
	"\x15IR_VERSION_2025_08_26\x10\f\x12\x0e\n" +
	"\n" +
	"IR_VERSION\x10\r*.\n" +
	"\x0eOperatorStatus\x12\x10\n" +
	"\fEXPERIMENTAL\x10\x00\x12\n" +
	"\n" +
	"\x06STABLE\x10\x01B\vH\x03Z\a./;onnx"

var (
	file_onnx_proto_rawDescOnce sync.Once
	file_onnx_proto_rawDescData []byte
)

func file_onnx_proto_rawDescGZIP() []byte {
	file_onnx_proto_rawDescOnce.Do(func() {
		file_onnx_proto_rawDescData = protoimpl.X.CompressGZIP(unsafe.Slice(unsafe.StringData(file_onnx_proto_rawDesc), len(file_onnx_proto_rawDesc)))
	})
	return file_onnx_proto_rawDescData
}

var file_onnx_proto_enumTypes = make([]protoimpl.EnumInfo, 5)
var file_onnx_proto_msgTypes = make([]protoimpl.MessageInfo, 27)
var file_onnx_proto_goTypes = []any{
	(Version)(0),                         // 0: onnx.Version
	(OperatorStatus)(0),                  // 1: onnx.OperatorStatus
	(AttributeProto_AttributeType)(0),    // 2: onnx.AttributeProto.AttributeType
	(TensorProto_DataType)(0),            // 3: onnx.TensorProto.DataType
	(TensorProto_DataLocation)(0),        // 4: onnx.TensorProto.DataLocation
	(*AttributeProto)(nil),               // 5: onnx.AttributeProto
	(*ValueInfoProto)(nil),               // 6: onnx.ValueInfoProto
	(*NodeProto)(nil),                    // 7: onnx.NodeProto
	(*IntIntListEntryProto)(nil),         // 8: onnx.IntIntListEntryProto
	(*NodeDeviceConfigurationProto)(nil), // 9: onnx.NodeDeviceConfigurationProto
	(*ShardingSpecProto)(nil),            // 10: onnx.ShardingSpecProto
	(*ShardedDimProto)(nil),              // 11: onnx.ShardedDimProto
	(*SimpleShardedDimProto)(nil),        // 12: onnx.SimpleShardedDimProto
	(*TrainingInfoProto)(nil),            // 13: onnx.TrainingInfoProto
	(*ModelProto)(nil),                   // 14: onnx.ModelProto
	(*DeviceConfigurationProto)(nil),     // 15: onnx.DeviceConfigurationProto
	(*StringStringEntryProto)(nil),       // 16: onnx.StringStringEntryProto
	(*TensorAnnotation)(nil),             // 17: onnx.TensorAnnotation
	(*GraphProto)(nil),                   // 18: onnx.GraphProto
	(*TensorProto)(nil),                  // 19: onnx.TensorProto
	(*SparseTensorProto)(nil),            // 20: onnx.SparseTensorProto
	(*TensorShapeProto)(nil),             // 21: onnx.TensorShapeProto
	(*TypeProto)(nil),                    // 22: onnx.TypeProto
	(*OperatorSetIdProto)(nil),           // 23: onnx.OperatorSetIdProto
	(*FunctionProto)(nil),                // 24: onnx.FunctionProto
	(*TensorProto_Segment)(nil),          // 25: onnx.TensorProto.Segment
	(*TensorShapeProto_Dimension)(nil),   // 26: onnx.TensorShapeProto.Dimension
	(*TypeProto_Tensor)(nil),             // 27: onnx.TypeProto.Tensor
	(*TypeProto_Sequence)(nil),           // 28: onnx.TypeProto.Sequence
	(*TypeProto_Map)(nil),                // 29: onnx.TypeProto.Map
	(*TypeProto_Optional)(nil),           // 30: onnx.TypeProto.Optional
	(*TypeProto_SparseTensor)(nil),       // 31: onnx.TypeProto.SparseTensor
}
var file_onnx_proto_depIdxs = []int32{
	2,  // 0: onnx.AttributeProto.type:type_name -> onnx.AttributeProto.AttributeType
	19, // 1: onnx.AttributeProto.t:type_name -> onnx.TensorProto
	18, // 2: onnx.AttributeProto.g:type_name -> onnx.GraphProto
	20, // 3: onnx.AttributeProto.sparse_tensor:type_name -> onnx.SparseTensorProto
	22, // 4: onnx.AttributeProto.tp:type_name -> onnx.TypeProto
	19, // 5: onnx.AttributeProto.tensors:type_name -> onnx.TensorProto
	18, // 6: onnx.AttributeProto.graphs:type_name -> onnx.GraphProto
	20, // 7: onnx.AttributeProto.sparse_tensors:type_name -> onnx.SparseTensorProto
	22, // 8: onnx.AttributeProto.type_protos:type_name -> onnx.TypeProto
	22, // 9: onnx.ValueInfoProto.type:type_name -> onnx.TypeProto
	16, // 10: onnx.ValueInfoProto.metadata_props:type_name -> onnx.StringStringEntryProto
	5,  // 11: onnx.NodeProto.attribute:type_name -> onnx.AttributeProto
	16, // 12: onnx.NodeProto.metadata_props:type_name -> onnx.StringStringEntryProto
	9,  // 13: onnx.NodeProto.device_configurations:type_name -> onnx.NodeDeviceConfigurationProto
	10, // 14: onnx.NodeDeviceConfigurationProto.sharding_spec:type_name -> onnx.ShardingSpecProto
	8,  // 15: onnx.ShardingSpecProto.index_to_device_group_map:type_name -> onnx.IntIntListEntryProto
	11, // 16: onnx.ShardingSpecProto.sharded_dim:type_name -> onnx.ShardedDimProto
	12, // 17: onnx.ShardedDimProto.simple_sharding:type_name -> onnx.SimpleShardedDimProto
	18, // 18: onnx.TrainingInfoProto.initialization:type_name -> onnx.GraphProto
	18, // 19: onnx.TrainingInfoProto.algorithm:type_name -> onnx.GraphProto
	16, // 20: onnx.TrainingInfoProto.initialization_binding:type_name -> onnx.StringStringEntryProto
	16, // 21: onnx.TrainingInfoProto.update_binding:type_name -> onnx.StringStringEntryProto
	23, // 22: onnx.ModelProto.opset_import:type_name -> onnx.OperatorSetIdProto
	18, // 23: onnx.ModelProto.graph:type_name -> onnx.GraphProto
	16, // 24: onnx.ModelProto.metadata_props:type_name -> onnx.StringStringEntryProto
	13, // 25: onnx.ModelProto.training_info:type_name -> onnx.TrainingInfoProto
	24, // 26: onnx.ModelProto.functions:type_name -> onnx.FunctionProto
	15, // 27: onnx.ModelProto.configuration:type_name -> onnx.DeviceConfigurationProto
	16, // 28: onnx.TensorAnnotation.quant_parameter_tensor_names:type_name -> onnx.StringStringEntryProto
	7,  // 29: onnx.GraphProto.node:type_name -> onnx.NodeProto
	19, // 30: onnx.GraphProto.initializer:type_name -> onnx.TensorProto
	20, // 31: onnx.GraphProto.sparse_initializer:type_name -> onnx.SparseTensorProto
	6,  // 32: onnx.GraphProto.input:type_name -> onnx.ValueInfoProto
	6,  // 33: onnx.GraphProto.output:type_name -> onnx.ValueInfoProto
	6,  // 34: onnx.GraphProto.value_info:type_name -> onnx.ValueInfoProto
	17, // 35: onnx.GraphProto.quantization_annotation:type_name -> onnx.TensorAnnotation
	16, // 36: onnx.GraphProto.metadata_props:type_name -> onnx.StringStringEntryProto
	25, // 37: onnx.TensorProto.segment:type_name -> onnx.TensorProto.Segment
	16, // 38: onnx.TensorProto.external_data:type_name -> onnx.StringStringEntryProto
	4,  // 39: onnx.TensorProto.data_location:type_name -> onnx.TensorProto.DataLocation
	16, // 40: onnx.TensorProto.metadata_props:type_name -> onnx.StringStringEntryProto
	19, // 41: onnx.SparseTensorProto.values:type_name -> onnx.TensorProto
	19, // 42: onnx.SparseTensorProto.indices:type_name -> onnx.TensorProto
	26, // 43: onnx.TensorShapeProto.dim:type_name -> onnx.TensorShapeProto.Dimension
	27, // 44: onnx.TypeProto.tensor_type:type_name -> onnx.TypeProto.Tensor
	28, // 45: onnx.TypeProto.sequence_type:type_name -> onnx.TypeProto.Sequence
	29, // 46: onnx.TypeProto.map_type:type_name -> onnx.TypeProto.Map
	30, // 47: onnx.TypeProto.optional_type:type_name -> onnx.TypeProto.Optional
	31, // 48: onnx.TypeProto.sparse_tensor_type:type_name -> onnx.TypeProto.SparseTensor
	5,  // 49: onnx.FunctionProto.attribute_proto:type_name -> onnx.AttributeProto
	7,  // 50: onnx.FunctionProto.node:type_name -> onnx.NodeProto
	23, // 51: onnx.FunctionProto.opset_import:type_name -> onnx.OperatorSetIdProto
	6,  // 52: onnx.FunctionProto.value_info:type_name -> onnx.ValueInfoProto
	16, // 53: onnx.FunctionProto.metadata_props:type_name -> onnx.StringStringEntryProto
	21, // 54: onnx.TypeProto.Tensor.shape:type_name -> onnx.TensorShapeProto
	22, // 55: onnx.TypeProto.Sequence.elem_type:type_name -> onnx.TypeProto
	22, // 56: onnx.TypeProto.Map.value_type:type_name -> onnx.TypeProto
	22, // 57: onnx.TypeProto.Optional.elem_type:type_name -> onnx.TypeProto
	21, // 58: onnx.TypeProto.SparseTensor.shape:type_name -> onnx.TensorShapeProto
	59, // [59:59] is the sub-list for method output_type
	59, // [59:59] is the sub-list for method input_type
	59, // [59:59] is the sub-list for extension type_name
	59, // [59:59] is the sub-list for extension extendee
	0,  // [0:59] is the sub-list for field type_name
}

func init() { file_onnx_proto_init() }
func file_onnx_proto_init() {
	if File_onnx_proto != nil {
		return
	}
	file_onnx_proto_msgTypes[7].OneofWrappers = []any{
		(*SimpleShardedDimProto_DimValue)(nil),
		(*SimpleShardedDimProto_DimParam)(nil),
	}
	file_onnx_proto_msgTypes[17].OneofWrappers = []any{
		(*TypeProto_TensorType)(nil),
		(*TypeProto_SequenceType)(nil),
		(*TypeProto_MapType)(nil),
		(*TypeProto_OptionalType)(nil),
		(*TypeProto_SparseTensorType)(nil),
	}
	file_onnx_proto_msgTypes[21].OneofWrappers = []any{
		(*TensorShapeProto_Dimension_DimValue)(nil),
		(*TensorShapeProto_Dimension_DimParam)(nil),
	}
	type x struct{}
	out := protoimpl.TypeBuilder{
		File: protoimpl.DescBuilder{
			GoPackagePath: reflect.TypeOf(x{}).PkgPath(),
			RawDescriptor: unsafe.Slice(unsafe.StringData(file_onnx_proto_rawDesc), len(file_onnx_proto_rawDesc)),
			NumEnums:      5,
			NumMessages:   27,
			NumExtensions: 0,
			NumServices:   0,
		},
		GoTypes:           file_onnx_proto_goTypes,
		DependencyIndexes: file_onnx_proto_depIdxs,
		EnumInfos:         file_onnx_proto_enumTypes,
		MessageInfos:      file_onnx_proto_msgTypes,
	}.Build()
	File_onnx_proto = out.File
	file_onnx_proto_goTypes = nil
	file_onnx_proto_depIdxs = nil
}
