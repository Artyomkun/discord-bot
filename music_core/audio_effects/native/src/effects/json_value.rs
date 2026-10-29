use serde::{Serialize, Deserialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct JsonValue(pub serde_json::Value);

impl JsonValue {
    pub fn new(value: serde_json::Value) -> Self { Self(value) }
    pub fn inner(&self) -> &serde_json::Value { &self.0 }
    pub fn into_inner(self) -> serde_json::Value { self.0 }
}

impl From<serde_json::Value> for JsonValue {
    fn from(value: serde_json::Value) -> Self { Self(value) }
}

impl From<JsonValue> for serde_json::Value {
    fn from(value: JsonValue) -> serde_json::Value { value.0 }
}

impl bincode::Encode for JsonValue {
    fn encode<E: bincode::enc::Encoder>(&self, encoder: &mut E) -> Result<(), bincode::error::EncodeError> {
        let s = serde_json::to_string(&self.0).map_err(|e| bincode::error::EncodeError::OtherString(e.to_string()))?;
        s.encode(encoder)
    }
}

impl<__Context> bincode::Decode<__Context> for JsonValue {
    fn decode<D: bincode::de::Decoder>(decoder: &mut D) -> Result<Self, bincode::error::DecodeError> {
        let s = String::decode(decoder)?;
        Ok(JsonValue(serde_json::from_str(&s).map_err(|e| bincode::error::DecodeError::OtherString(e.to_string()))?))
    }
}

impl<'de, __Context> bincode::BorrowDecode<'de, __Context> for JsonValue {
    fn borrow_decode<D: bincode::de::BorrowDecoder<'de>>(decoder: &mut D) -> Result<Self, bincode::error::DecodeError> {
        let s = String::borrow_decode(decoder)?;
        Ok(JsonValue(serde_json::from_str(&s).map_err(|e| bincode::error::DecodeError::OtherString(e.to_string()))?))
    }
}