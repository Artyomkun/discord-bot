package main

import (
	"context"
	"log"
	"net"
	"sync"
	"time"

	"google.golang.org/grpc"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"

	pb "goserver" // замени на правильный import path
)

type server struct {
	pb.UnimplementedGoServerServer
	mu         sync.RWMutex
	queues     map[string]*QueueState
	javaClient pb.GoClientClient // клиент для Java Gateway
}

type QueueState struct {
	Tracks        []*pb.TrackInfo
	CurrentTrack  *pb.TrackInfo
	CurrentPosMs  int32
	Volume        int32
	Loop          bool
	Shuffle       bool
	Playing       bool
	Paused        bool
	StartedAt     int64
	PausedAt      int64
	History       []*pb.TrackInfo
}

func NewServer() *server {
	return &server{
		queues: make(map[string]*QueueState),
	}
}

func (s *server) searchLocally(query, userId string) *pb.TrackInfo {
	return &pb.TrackInfo{
		Id:            time.Now().Format("20060102150405"),
		Title:         query,
		Artist:        "Unknown",
		Duration:      "0:00",
		DurationMs:    0,
		Url:           query,
		Thumbnail:     "",
		RequesterId:   userId,
		RequesterName: "User",
		RequestedAt:   time.Now().Unix(),
	}
}

func (s *server) getQueue(guildId string) *QueueState {
	s.mu.Lock()
	defer s.mu.Unlock()
	
	if _, exists := s.queues[guildId]; !exists {
		s.queues[guildId] = &QueueState{
			Tracks:   []*pb.TrackInfo{},
			Volume:   50,
			History:  []*pb.TrackInfo{},
		}
	}
	return s.queues[guildId]
}

// ========== Управление воспроизведением ==========

func (s *server) Play(ctx context.Context, req *pb.PlayRequest) (*pb.PlayResponse, error) {
	log.Printf("🎵 Play request: guild=%s, user=%s, query=%s", req.GuildId, req.UserId, req.Query)
	
	queue := s.getQueue(req.GuildId)
	
	track, err := s.javaClient.Search(ctx, &pb.SearchRequest{
		Query:  req.Query,
		UserId: req.UserId,
		Limit:  1,
	})
	if err != nil {
		// Java не ответил — Go ищет сам
		track = s.searchLocally(req.Query, req.UserId)
	}
		
	queue.Tracks = append(queue.Tracks, track)
	
	if !queue.Playing && queue.CurrentTrack == nil {
		// Начинаем воспроизведение
		queue.CurrentTrack = track
		queue.Playing = true
		queue.StartedAt = time.Now().Unix()
		queue.CurrentPosMs = 0
		
		return &pb.PlayResponse{
			Success:     true,
			Message:     "Playing",
			Track:       track,
			Position:    1,
			QueueLength: int32(len(queue.Tracks)),
		}, nil
	}
	
	return &pb.PlayResponse{
		Success:     true,
		Message:     "Added to queue",
		Track:       track,
		Position:    int32(len(queue.Tracks)),
		QueueLength: int32(len(queue.Tracks)),
	}, nil
}

func (s *server) Stop(ctx context.Context, req *pb.StopRequest) (*pb.StopResponse, error) {
	log.Printf("⏹️ Stop request: guild=%s", req.GuildId)
	
	queue := s.getQueue(req.GuildId)
	queue.Playing = false
	queue.CurrentTrack = nil
	queue.Tracks = []*pb.TrackInfo{}
	queue.CurrentPosMs = 0
	
	return &pb.StopResponse{
		Success: true,
		Message: "Stopped",
	}, nil
}

func (s *server) Pause(ctx context.Context, req *pb.PauseRequest) (*pb.PauseResponse, error) {
	log.Printf("⏸️ Pause request: guild=%s", req.GuildId)
	
	queue := s.getQueue(req.GuildId)
	if queue.Playing && !queue.Paused {
		queue.Paused = true
		queue.PausedAt = time.Now().Unix()
	}
	
	return &pb.PauseResponse{
		Success: true,
		Message: "Paused",
	}, nil
}

func (s *server) Resume(ctx context.Context, req *pb.ResumeRequest) (*pb.ResumeResponse, error) {
	log.Printf("▶️ Resume request: guild=%s", req.GuildId)
	
	queue := s.getQueue(req.GuildId)
	if queue.Paused {
		queue.Paused = false
	}
	
	return &pb.ResumeResponse{
		Success: true,
		Message: "Resumed",
	}, nil
}

func (s *server) Skip(ctx context.Context, req *pb.SkipRequest) (*pb.SkipResponse, error) {
	log.Printf("⏭️ Skip request: guild=%s, count=%d", req.GuildId, req.Count)
	
	queue := s.getQueue(req.GuildId)
	
	if len(queue.Tracks) == 0 {
		return &pb.SkipResponse{
			Success: false,
			Message: "No tracks in queue",
			HasNext: false,
		}, nil
	}
	
	prevTrack := queue.CurrentTrack
	
	// Пропускаем count треков
	skipCount := int(req.Count)
	if skipCount > len(queue.Tracks) {
		skipCount = len(queue.Tracks)
	}
	
	if skipCount > 0 {
		queue.Tracks = queue.Tracks[skipCount-1:]
	}
	
	if len(queue.Tracks) > 0 {
		queue.CurrentTrack = queue.Tracks[0]
		queue.Tracks = queue.Tracks[1:]
		queue.CurrentPosMs = 0
		queue.StartedAt = time.Now().Unix()
		
		return &pb.SkipResponse{
			Success:      true,
			Message:      "Skipped",
			PreviousTrack: prevTrack,
			CurrentTrack:  queue.CurrentTrack,
			HasNext:       len(queue.Tracks) > 0,
		}, nil
	}
	
	queue.CurrentTrack = nil
	queue.Playing = false
	
	return &pb.SkipResponse{
		Success: true,
		Message: "Skipped, queue empty",
		HasNext: false,
	}, nil
}

func (s *server) Seek(ctx context.Context, req *pb.SeekRequest) (*pb.SeekResponse, error) {
	log.Printf("⏩ Seek request: guild=%s, position=%dms", req.GuildId, req.PositionMs)
	
	queue := s.getQueue(req.GuildId)
	queue.CurrentPosMs = req.PositionMs
	
	return &pb.SeekResponse{
		Success:       true,
		Message:       "Seeked",
		NewPositionMs: req.PositionMs,
	}, nil
}

// ========== Управление очередью ==========

func (s *server) GetQueue(ctx context.Context, req *pb.QueueRequest) (*pb.QueueResponse, error) {
	queue := s.getQueue(req.GuildId)
	
	var totalDuration int32
	for _, track := range queue.Tracks {
		totalDuration += track.DurationMs
	}
	
	return &pb.QueueResponse{
		Success:           true,
		Message:           "OK",
		CurrentTrack:      queue.CurrentTrack,
		CurrentPositionMs: queue.CurrentPosMs,
		Tracks:            queue.Tracks,
		Total:             int32(len(queue.Tracks)),
		DurationMs:        totalDuration,
		Loop:              queue.Loop,
		Shuffle:           queue.Shuffle,
	}, nil
}

func (s *server) AddToQueue(ctx context.Context, req *pb.AddToQueueRequest) (*pb.AddToQueueResponse, error) {
	log.Printf("📝 AddToQueue: guild=%s, query=%s, position=%d", req.GuildId, req.Query, req.Position)
	
	queue := s.getQueue(req.GuildId)
	
	track := &pb.TrackInfo{
		Id:          time.Now().Format("20060102150405"),
		Title:       req.Query,
		Artist:      "Unknown",
		Duration:    "0:00",
		DurationMs:  0,
		Url:         req.Query,
		Thumbnail:   "",
		RequesterId: req.UserId,
		RequesterName: "User",
		RequestedAt: time.Now().Unix(),
	}
	
	pos := int(req.Position)
	if pos <= 0 || pos > len(queue.Tracks) {
		queue.Tracks = append(queue.Tracks, track)
		pos = len(queue.Tracks)
	} else {
		queue.Tracks = append(queue.Tracks[:pos], append([]*pb.TrackInfo{track}, queue.Tracks[pos:]...)...)
	}
	
	return &pb.AddToQueueResponse{
		Success:     true,
		Message:     "Added to queue",
		Track:       track,
		Position:    int32(pos),
		QueueLength: int32(len(queue.Tracks)),
	}, nil
}

func (s *server) RemoveFromQueue(ctx context.Context, req *pb.RemoveFromQueueRequest) (*pb.RemoveFromQueueResponse, error) {
	log.Printf("❌ RemoveFromQueue: guild=%s, position=%d", req.GuildId, req.Position)
	
	queue := s.getQueue(req.GuildId)
	pos := int(req.Position)
	
	if pos < 1 || pos > len(queue.Tracks) {
		return &pb.RemoveFromQueueResponse{
			Success: false,
			Message: "Invalid position",
		}, nil
	}
	
	removed := queue.Tracks[pos-1]
	queue.Tracks = append(queue.Tracks[:pos-1], queue.Tracks[pos:]...)
	
	return &pb.RemoveFromQueueResponse{
		Success:      true,
		Message:      "Removed from queue",
		RemovedTrack: removed,
		QueueLength:  int32(len(queue.Tracks)),
	}, nil
}

func (s *server) MoveInQueue(ctx context.Context, req *pb.MoveInQueueRequest) (*pb.MoveInQueueResponse, error) {
	log.Printf("🔀 MoveInQueue: guild=%s, from=%d, to=%d", req.GuildId, req.FromPosition, req.ToPosition)
	
	queue := s.getQueue(req.GuildId)
	from := int(req.FromPosition) - 1
	to := int(req.ToPosition) - 1
	
	if from < 0 || from >= len(queue.Tracks) || to < 0 || to >= len(queue.Tracks) {
		return &pb.MoveInQueueResponse{
			Success: false,
			Message: "Invalid positions",
		}, nil
	}
	
	track := queue.Tracks[from]
	queue.Tracks = append(queue.Tracks[:from], queue.Tracks[from+1:]...)
	queue.Tracks = append(queue.Tracks[:to], append([]*pb.TrackInfo{track}, queue.Tracks[to:]...)...)
	
	return &pb.MoveInQueueResponse{
		Success:    true,
		Message:    "Moved in queue",
		MovedTrack: track,
	}, nil
}

func (s *server) ClearQueue(ctx context.Context, req *pb.ClearQueueRequest) (*pb.ClearQueueResponse, error) {
	log.Printf("🗑️ ClearQueue: guild=%s", req.GuildId)
	
	queue := s.getQueue(req.GuildId)
	cleared := len(queue.Tracks)
	queue.Tracks = []*pb.TrackInfo{}
	
	return &pb.ClearQueueResponse{
		Success:      true,
		Message:      "Queue cleared",
		ClearedCount: int32(cleared),
	}, nil
}

func (s *server) ShuffleQueue(ctx context.Context, req *pb.ShuffleQueueRequest) (*pb.ShuffleQueueResponse, error) {
	log.Printf("🔄 ShuffleQueue: guild=%s", req.GuildId)
	
	queue := s.getQueue(req.GuildId)
	// Простое перемешивание
	for i := len(queue.Tracks) - 1; i > 0; i-- {
		j := int(time.Now().UnixNano() % int64(i+1))
		queue.Tracks[i], queue.Tracks[j] = queue.Tracks[j], queue.Tracks[i]
	}
	
	return &pb.ShuffleQueueResponse{
		Success:       true,
		Message:       "Queue shuffled",
		ShuffledCount: int32(len(queue.Tracks)),
	}, nil
}

// ========== Управление громкостью ==========

func (s *server) SetVolume(ctx context.Context, req *pb.VolumeRequest) (*pb.VolumeResponse, error) {
	log.Printf("🔊 SetVolume: guild=%s, volume=%d", req.GuildId, req.Volume)
	
	queue := s.getQueue(req.GuildId)
	queue.Volume = req.Volume
	
	return &pb.VolumeResponse{
		Success: true,
		Message: "Volume set",
		Volume:  req.Volume,
	}, nil
}

// ========== Статус и информация ==========

func (s *server) GetStatus(ctx context.Context, req *pb.StatusRequest) (*pb.StatusResponse, error) {
	queue := s.getQueue(req.GuildId)
	
	return &pb.StatusResponse{
		Success:           true,
		Playing:           queue.Playing,
		Paused:            queue.Paused,
		CurrentTrack:      queue.CurrentTrack,
		CurrentPositionMs: queue.CurrentPosMs,
		Volume:            queue.Volume,
		QueueLength:       int32(len(queue.Tracks)),
		Loop:              queue.Loop,
		Shuffle:           queue.Shuffle,
		VoiceChannelId:    "",
		StartedAt:         queue.StartedAt,
		PausedAt:          queue.PausedAt,
	}, nil
}

func (s *server) GetHistory(ctx context.Context, req *pb.HistoryRequest) (*pb.HistoryResponse, error) {
	queue := s.getQueue(req.GuildId)
	
	limit := int(req.Limit)
	if limit <= 0 || limit > len(queue.History) {
		limit = len(queue.History)
	}
	
	var tracks []*pb.TrackInfo
	if limit > 0 {
		tracks = queue.History[len(queue.History)-limit:]
	}
	
	return &pb.HistoryResponse{
		Success: true,
		Tracks:  tracks,
		Total:   int32(len(queue.History)),
	}, nil
}

// ========== Health Check ==========

func (s *server) HealthCheck(ctx context.Context, req *pb.HealthRequest) (*pb.HealthResponse, error) {
	return &pb.HealthResponse{
		Status:    "SERVING",
		Message:   "GoServer is healthy",
		Timestamp: time.Now().Unix(),
		Checks:    map[string]*pb.HealthCheck{},
	}, nil
}

func main() {
	lis, err := net.Listen("tcp", ":8082")
	if err != nil {
		log.Fatalf("Failed to listen: %v", err)
	}
	
	grpcServer := grpc.NewServer()
	pb.RegisterGoServerServer(grpcServer, NewServer())
	
	log.Println("🚀 GoServer listening on :8082")
	if err := grpcServer.Serve(lis); err != nil {
		log.Fatalf("Failed to serve: %v", err)
	}
}