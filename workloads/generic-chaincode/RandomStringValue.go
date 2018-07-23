package main

import (
	"math/rand"
)

// RandomStringValue represents a random string value
type RandomStringValue struct {
	myrandsrc rand.Source
	myrand    *rand.Rand
	key       string
	val       string
}

// http://stackoverflow.com/a/31832326
const letterBytes = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
const (
	letterIdxBits = 6                    // 6 bits to represent a letter index
	letterIdxMask = 1<<letterIdxBits - 1 // All 1-bits, as many as letterIdxBits
	letterIdxMax  = 63 / letterIdxBits   // # of letter indices fitting in 63 bits
)

// RandStringBytesMaskImprSrc generates a random string of english letters of length n
func (r *RandomStringValue) RandStringBytesMaskImprSrc(n int) string {
	src := r.myrandsrc
	b := make([]byte, n)
	// A src.Int63() generates 63 random bits, enough for letterIdxMax characters!
	for i, cache, remain := n-1, src.Int63(), letterIdxMax; i >= 0; {
		if remain == 0 {
			cache, remain = src.Int63(), letterIdxMax
		}
		if idx := int(cache & letterIdxMask); idx < len(letterBytes) {
			b[i] = letterBytes[idx]
			i--
		}
		cache >>= letterIdxBits
		remain--
	}

	return string(b)
}

// Init initializes a new RandomStringValue instance
func (r *RandomStringValue) Init(seed int) {
	r.myrandsrc = rand.NewSource(int64(seed))
	r.myrand = rand.New(r.myrandsrc)
}

// GetKey returns the key of this value
func (r *RandomStringValue) GetKey() string {
	return r.key
}

// SetKey sets the key of the value
func (r *RandomStringValue) SetKey(k string) {
	r.key = k
}

// Generate takes a key and initializes a random value
func (r *RandomStringValue) Generate(key string, valSizeLo int, valSizeHi int) {
	n := r.myrand.Intn(valSizeHi-valSizeLo+1) + valSizeLo
	r.val = r.RandStringBytesMaskImprSrc(n)
	r.key = key
}

// Parse takes a string and stores it in the struct.
func (r *RandomStringValue) Parse(v string) {
	r.val = v
}

// SerializeForState returns the stored string
func (r *RandomStringValue) SerializeForState() string {
	return r.val
}

// GetJSONObject returns the stored string as a JSON object - {"Key":"Value"}
func (r *RandomStringValue) GetJSONObject() string {
	return "{\"" + r.key + "\":\"" + r.val + "\"}"
}
