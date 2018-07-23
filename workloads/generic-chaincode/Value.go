package main

import "bytes"

// Value is an interface to represent values. We have values
// of two types - RandomStringValue and JSONValue. Can add more.
type Value interface {
	Init(seed int)
	GetKey() string
	SetKey(string)
	Generate(key string, valSizeLo int, valSizeHi int)
	Parse(v string)
	SerializeForState() string
	GetJSONObject() string
}

// MakeJSONArray takes a slice of Value and returns the corresponding JSON string
func MakeJSONArray(values []Value) string {
	var buffer bytes.Buffer
	buffer.WriteString("[")

	for i, v := range values {
		buffer.WriteString(v.GetJSONObject())
		if i != len(values)-1 {
			buffer.WriteString(",")
		}
	}

	buffer.WriteString("]")
	return buffer.String()
}
