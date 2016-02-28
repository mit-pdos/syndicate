package gfs

import "time"

// ChunkHandle is a unique identifier for a single chunk in GFS.
type ChunkHandle uint64

// Chunk identifies the identity and version of a single GFS chunk.
type Chunk struct {
	Handle  ChunkHandle
	Version int
}

// RegisterArgs is the argument to Master.Register()
type RegisterArgs struct {
	MyIP   string
	Chunks []Chunk
}

// LocateArgs is the argument to Master.Locate()
type LocateArgs struct {
	File  string
	Chunk int
}

// LocateReply is the reply from Master.Locate()
type LocateReply struct {
	Chunk   Chunk
	Primary []string
	Servers []string

	// DataOrder tells the client in what order it should push data to
	// chunkservers. Specifically, the client will send a Push() RPC to the
	// first server in this list, with ForwardTo = DataOrder[1:].
	DataOrder []string
}

// FileArg is a filename.
type FileArg string

// CreateArgs is the argument to Master.Create()
type CreateArgs FileArg

// DeleteArgs is the argument to Master.Delete()
type DeleteArgs FileArg

// SnapshotArgs is the argument to Master.Snapshot()
type SnapshotArgs struct {
	File string

	// Into is the name of the file that the snapshot should be put into.
	Into string
}

// Master is the interface your GFS master should implement. This interface
// will be used by the lab client to test and benchmark your solution.
type Master interface {
	// Chunk server interaction

	// Register registers a new chunkserver.
	Register(args *RegisterArgs, reply *struct{}) error
	// Servers should return the list of all known, active chunkservers.
	// This is used by the tester.
	Servers(args *struct{}, reply *[]string) error

	// Client

	// Locate tells a client which chunkservers are responsible for a given
	// chunk of a given file.
	Locate(args *LocateArgs, reply *LocateReply) error

	// Namespace operations

	// Create creates a new (empty) file.
	Create(args *CreateArgs, reply *struct{}) error

	// Delete deletes a file from GFS.
	Delete(args *DeleteArgs, reply *struct{}) error

	// Snapshot makes an instantaneous GFS snapshot of the given file or
	// directory.
	Snapshot(args *SnapshotArgs, reply *struct{}) error
}

// DataIdent is an ephemeral unique identifier for data that has been pushed to
// a chunkserver, but which has not yet been written into a chunk.
type DataIdent uint64

// ReadArgs is the argument to Chunkserver.Read()
type ReadArgs struct {
	Handle Chunk
	Start  int
	End    int
}

// WriteArgs is the argument to Chunkserver.Write()
type WriteArgs struct {
	Handle Chunk
	Offset int
	Data   DataIdent
}

// AppendArgs is the argument to Chunkserver.Append()
type AppendArgs struct {
	Handle Chunk
	Data   DataIdent
}

// PushArgs is the argument to Chunkserver.Push()
type PushArgs struct {
	Data  []byte
	Ident DataIdent

	// ForwardTo tells the chunkserver in what order it should push data to
	// other chunkservers. Specifically, the chunkserver will send a Push()
	// RPC to the next server in this list, with ForwardTo = ForwardTo[1:].
	ForwardTo []string
}

// MutateArgs is the argument to Chunkserver.Mutate()
type MutateArgs struct {
	Handle Chunk
	Offset int
	Data   DataIdent
}

// GrantArgs is the argument to Chunkserver.GrantLease()
type GrantArgs struct {
	Handle  Chunk
	Expires time.Time
}

// RevokeArgs is the argument to Chunkserver.RevokeLease()
type RevokeArgs Chunk

// Chunkserver is the interface your GFS chunkservers should implement. This
// interface will be used by the lab client to test and benchmark your
// solution. It also gives a good starting point for how the Master should
// communicate with the chunkservers.
type Chunkserver interface {
	// Client operations

	// Read reads a range of bytes from the given chunk.
	Read(args *ReadArgs, reply *[]byte) error

	// Write writes bytes into a specified offset in a chunk.
	Write(args *WriteArgs, reply *struct{}) error

	// Write performs an "atomic record append" operation on a chunk.
	Append(args *AppendArgs, reply *struct{}) error

	// Data flow

	// Push pushes data that a client wishes to write to a chunkserver.
	// This does not update any chunks, but simply caches the data to be
	// written at each chunkserver before the operation takes place. Data
	// that has been pushed, but that has not been written in a long time
	// should be garbage collected.
	Push(args *PushArgs, reply *struct{}) error

	// Primary operations

	// Mutate is an instruction from the chunk primary to perform a write
	// to a chunk.
	Mutate(args *MutateArgs, reply *struct{}) error

	// Master operations

	// GrantLease is called by the master to give this chunkserver a
	// primary lease for a chunk.
	GrantLease(args *GrantArgs, reply *struct{}) error

	// Revoke is called by the master to revoke this chunkserver's primary
	// lease for a chunk.
	RevokeLease(args *RevokeArgs, reply *struct{}) error

	// Heartbeat is used by the master to periodically check if a
	// chunkserver is still up.
	Heartbeat(args *struct{}, reply *struct{}) error
}
