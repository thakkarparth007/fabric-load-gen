package main

import (
	"math/rand"
	"strconv"
)

// KeyMapper is an interface that is used to
// map integer keys to strings. There can be various
// implementations. Simplest one is no-op.
type KeyMapper interface {
	Map(k int) string
	GetKeys(seed, nKeys, keySizeLo, keySizeHi int) []string
}

// NoopKeyMapper maps integers to their string representations
type NoopKeyMapper struct{}

// Map maps integers to their string representations
func (n *NoopKeyMapper) Map(k int) string {
	return strconv.Itoa(k)
}

// GetKeys returns a slice of strings having keys of lengths between keySizeLo and keySizeHi
func (n *NoopKeyMapper) GetKeys(seed, nKeys, keySizeLo, keySizeHi int) []string {
	myrand := rand.New(rand.NewSource(int64(seed)))
	var keys []string //:= make([]string, nKeys)
	for i := 0; i < nKeys; i++ {
		x := myrand.Intn(keySizeHi-keySizeLo+1) + keySizeLo
		keys = append(keys, strconv.Itoa(x))
	}
	return keys
}
