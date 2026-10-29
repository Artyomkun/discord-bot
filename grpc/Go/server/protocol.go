package main

import (
	"encoding/json"
	"fmt"
	"log"
	"regexp"
	"strings"
	"sync/atomic"
	"time"
	"sync"

	pb "goserver"
)

// CommandType — тип команды
type CommandType string

const (
	CmdPlay    CommandType = "play"
	CmdStop    CommandType = "stop"
	CmdPause   CommandType = "pause"
	CmdResume  CommandType = "resume"
	CmdSkip    CommandType = "skip"
	CmdSeek    CommandType = "seek"
	CmdQueue   CommandType = "queue"
	CmdVolume  CommandType = "volume"
	CmdSearch  CommandType = "search"
	CmdLoop    CommandType = "loop"
	CmdShuffle CommandType = "shuffle"
	CmdClear   CommandType = "clear"
	CmdRemove  CommandType = "remove"
	CmdMove    CommandType = "move"
	CmdEffect  CommandType = "effect"
	CmdStatus  CommandType = "status"
)

// CommandMetrics — метрики команд
type CommandMetrics struct {
	TotalCommands   int64
	ProcessedCommands int64
	FailedCommands  int64
	AvgDuration     time.Duration
	ByType          map[CommandType]*CommandTypeMetrics
	mu              sync.RWMutex
}

// CommandTypeMetrics — метрики по типу команды
type CommandTypeMetrics struct {
	Count       int64
	Failed      int64
	TotalDuration time.Duration
}

// Command — структура команды
type Command struct {
	Type      CommandType
	UserID    string
	GuildID   string
	ChannelID string
	Params    map[string]string
	Raw       string
	Timestamp time.Time
}

// Глобальные метрики команд
var commandMetrics = &CommandMetrics{
	ByType: make(map[CommandType]*CommandTypeMetrics),
}

// RecordCommand записывает выполнение команды
func RecordCommand(cmdType CommandType, duration time.Duration, success bool) {
	atomic.AddInt64(&commandMetrics.TotalCommands, 1)
	if success {
		atomic.AddInt64(&commandMetrics.ProcessedCommands, 1)
	} else {
		atomic.AddInt64(&commandMetrics.FailedCommands, 1)
	}

	// Обновляем среднюю длительность
	processed := atomic.LoadInt64(&commandMetrics.ProcessedCommands)
	if processed > 0 {
		oldAvg := commandMetrics.AvgDuration
		newAvg := time.Duration((int64(oldAvg)*(processed-1) + int64(duration)) / processed)
		commandMetrics.mu.Lock()
		commandMetrics.AvgDuration = newAvg
		commandMetrics.mu.Unlock()
	}

	// Обновляем метрики по типу
	commandMetrics.mu.Lock()
	if _, exists := commandMetrics.ByType[cmdType]; !exists {
		commandMetrics.ByType[cmdType] = &CommandTypeMetrics{}
	}
	cmdMetrics := commandMetrics.ByType[cmdType]
	cmdMetrics.Count++
	if !success {
		cmdMetrics.Failed++
	}
	cmdMetrics.TotalDuration += duration
	commandMetrics.mu.Unlock()
}

// GetCommandMetrics возвращает метрики команд
func GetCommandMetrics() *CommandMetrics {
	commandMetrics.mu.RLock()
	defer commandMetrics.mu.RUnlock()

	metrics := &CommandMetrics{
		TotalCommands:     atomic.LoadInt64(&commandMetrics.TotalCommands),
		ProcessedCommands: atomic.LoadInt64(&commandMetrics.ProcessedCommands),
		FailedCommands:    atomic.LoadInt64(&commandMetrics.FailedCommands),
		AvgDuration:       commandMetrics.AvgDuration,
		ByType:            make(map[CommandType]*CommandTypeMetrics),
	}

	for cmdType, m := range commandMetrics.ByType {
		metrics.ByType[cmdType] = &CommandTypeMetrics{
			Count:         m.Count,
			Failed:        m.Failed,
			TotalDuration: m.TotalDuration,
		}
	}

	return metrics
}

// ParseCommand парсит текстовую команду из Discord
func ParseCommand(text string, userID, guildID, channelID string) *Command {
	text = strings.TrimSpace(text)

	// Убираем упоминание бота
	text = regexp.MustCompile(`^<@!?\d+>\s*`).ReplaceAllString(text, "")

	parts := strings.Fields(text)
	if len(parts) == 0 {
		return nil
	}

	cmd := &Command{
		Type:      CommandType(strings.ToLower(parts[0])),
		UserID:    userID,
		GuildID:   guildID,
		ChannelID: channelID,
		Params:    make(map[string]string),
		Raw:       text,
		Timestamp: time.Now(),
	}

	// Парсим параметры
	switch cmd.Type {
	case CmdPlay:
		if len(parts) > 1 {
			cmd.Params["query"] = strings.Join(parts[1:], " ")
		}
	case CmdSkip:
		if len(parts) > 1 {
			cmd.Params["count"] = parts[1]
		}
	case CmdVolume:
		if len(parts) > 1 {
			cmd.Params["volume"] = parts[1]
		}
	case CmdSeek:
		if len(parts) > 1 {
			cmd.Params["position"] = parts[1]
		}
	case CmdRemove:
		if len(parts) > 1 {
			cmd.Params["position"] = parts[1]
		}
	case CmdMove:
		if len(parts) > 2 {
			cmd.Params["from"] = parts[1]
			cmd.Params["to"] = parts[2]
		}
	case CmdEffect:
		if len(parts) > 1 {
			cmd.Params["effect"] = parts[1]
			if len(parts) > 2 {
				cmd.Params["intensity"] = parts[2]
			}
		}
	}

	return cmd
}

// ValidateCommand проверяет валидность команды
func (c *Command) Validate() error {
	if c.UserID == "" {
		return fmt.Errorf("user_id is required")
	}
	if c.GuildID == "" && c.Type != CmdSearch {
		return fmt.Errorf("guild_id is required for command %s", c.Type)
	}

	switch c.Type {
	case CmdPlay:
		if c.Params["query"] == "" {
			return fmt.Errorf("query is required for play command")
		}
	case CmdVolume:
		vol := c.Params["volume"]
		if vol == "" {
			return fmt.Errorf("volume value is required")
		}
	case CmdSeek:
		if c.Params["position"] == "" {
			return fmt.Errorf("position is required for seek command")
		}
	case CmdRemove:
		if c.Params["position"] == "" {
			return fmt.Errorf("position is required for remove command")
		}
	case CmdMove:
		if c.Params["from"] == "" || c.Params["to"] == "" {
			return fmt.Errorf("from and to positions are required for move command")
		}
	}

	return nil
}

// ToPlayRequest преобразует команду в protobuf запрос
func (c *Command) ToPlayRequest() *pb.PlayRequest {
	return &pb.PlayRequest{
		GuildId:        c.GuildID,
		UserId:         c.UserID,
		Query:          c.Params["query"],
		VoiceChannelId: c.Params["voice_channel"],
		Options:        c.Params,
	}
}

func (c *Command) ToStopRequest() *pb.StopRequest {
	return &pb.StopRequest{
		GuildId: c.GuildID,
		UserId:  c.UserID,
	}
}

func (c *Command) ToPauseRequest() *pb.PauseRequest {
	return &pb.PauseRequest{
		GuildId: c.GuildID,
		UserId:  c.UserID,
	}
}

func (c *Command) ToResumeRequest() *pb.ResumeRequest {
	return &pb.ResumeRequest{
		GuildId: c.GuildID,
		UserId:  c.UserID,
	}
}

func (c *Command) ToSkipRequest() *pb.SkipRequest {
	count := int32(1)
	if c.Params["count"] != "" {
		fmt.Sscanf(c.Params["count"], "%d", &count)
	}
	return &pb.SkipRequest{
		GuildId: c.GuildID,
		UserId:  c.UserID,
		Count:   count,
	}
}

func (c *Command) ToSeekRequest() *pb.SeekRequest {
	var pos int32
	fmt.Sscanf(c.Params["position"], "%d", &pos)
	return &pb.SeekRequest{
		GuildId:    c.GuildID,
		UserId:     c.UserID,
		PositionMs: pos,
	}
}

func (c *Command) ToVolumeRequest() *pb.VolumeRequest {
	var vol int32
	fmt.Sscanf(c.Params["volume"], "%d", &vol)
	return &pb.VolumeRequest{
		GuildId: c.GuildID,
		UserId:  c.UserID,
		Volume:  vol,
	}
}

func (c *Command) ToQueueRequest() *pb.QueueRequest {
	return &pb.QueueRequest{
		GuildId: c.GuildID,
		UserId:  c.UserID,
	}
}

func (c *Command) ToClearQueueRequest() *pb.ClearQueueRequest {
	return &pb.ClearQueueRequest{
		GuildId: c.GuildID,
		UserId:  c.UserID,
	}
}

func (c *Command) ToShuffleQueueRequest() *pb.ShuffleQueueRequest {
	return &pb.ShuffleQueueRequest{
		GuildId: c.GuildID,
		UserId:  c.UserID,
	}
}

func (c *Command) ToRemoveFromQueueRequest() *pb.RemoveFromQueueRequest {
	var pos int32
	fmt.Sscanf(c.Params["position"], "%d", &pos)
	return &pb.RemoveFromQueueRequest{
		GuildId:  c.GuildID,
		UserId:   c.UserID,
		Position: pos,
	}
}

func (c *Command) ToMoveInQueueRequest() *pb.MoveInQueueRequest {
	var from, to int32
	fmt.Sscanf(c.Params["from"], "%d", &from)
	fmt.Sscanf(c.Params["to"], "%d", &to)
	return &pb.MoveInQueueRequest{
		GuildId:      c.GuildID,
		UserId:       c.UserID,
		FromPosition: from,
		ToPosition:   to,
	}
}

func (c *Command) ToEffectsRequest() *pb.EffectsRequest {
	intensity := 0.5
	if c.Params["intensity"] != "" {
		fmt.Sscanf(c.Params["intensity"], "%f", &intensity)
	}
	return &pb.EffectsRequest{
		GuildId:    c.GuildID,
		UserId:     c.UserID,
		EffectType: c.Params["effect"],
		Intensity:  intensity,
		Params:     c.Params,
	}
}

func (c *Command) ToStatusRequest() *pb.StatusRequest {
	return &pb.StatusRequest{
		GuildId: c.GuildID,
		UserId:  c.UserID,
	}
}

func (c *Command) ToSearchRequest() *pb.SearchRequest {
	return &pb.SearchRequest{
		GuildId:  c.GuildID,
		UserId:   c.UserID,
		Query:    c.Params["query"],
		Platform: c.Params["platform"],
		Limit:    5,
	}
}

// FormatDuration форматирует длительность в мм:сс
func FormatDuration(ms int32) string {
	seconds := ms / 1000
	minutes := seconds / 60
	seconds = seconds % 60
	return fmt.Sprintf("%d:%02d", minutes, seconds)
}

// FormatTrackInfo форматирует трек для вывода
func FormatTrackInfo(track *pb.TrackInfo) string {
	if track == nil {
		return "Nothing playing"
	}
	return fmt.Sprintf("**%s** by %s (%s) — requested by <@%s>",
		track.Title,
		track.Artist,
		FormatDuration(track.DurationMs),
		track.RequesterId,
	)
}

// FormatQueue форматирует очередь для вывода
func FormatQueue(queue *pb.QueueResponse) string {
	if !queue.Success {
		return "Error: " + queue.Message
	}

	if len(queue.Tracks) == 0 && queue.CurrentTrack == nil {
		return "Queue is empty"
	}

	var sb strings.Builder

	// Current track
	if queue.CurrentTrack != nil {
		sb.WriteString("🎵 **Currently playing:**\n")
		sb.WriteString("  " + FormatTrackInfo(queue.CurrentTrack) + "\n\n")
	}

	// Queue
	if len(queue.Tracks) > 0 {
		sb.WriteString("📋 **Queue:**\n")
		maxDisplay := 10
		if len(queue.Tracks) < maxDisplay {
			maxDisplay = len(queue.Tracks)
		}
		for i := 0; i < maxDisplay; i++ {
			track := queue.Tracks[i]
			sb.WriteString(fmt.Sprintf("  %d. %s by %s (%s)\n",
				i+1,
				track.Title,
				track.Artist,
				FormatDuration(track.DurationMs),
			))
		}
		if len(queue.Tracks) > 10 {
			sb.WriteString(fmt.Sprintf("  ... and %d more tracks\n", len(queue.Tracks)-10))
		}
		sb.WriteString(fmt.Sprintf("\n📊 **Total duration:** %s", FormatDuration(queue.DurationMs)))
	}

	return sb.String()
}

// FormatStatus форматирует статус для вывода
func FormatStatus(status *pb.StatusResponse) string {
	if !status.Success {
		return "Error getting status"
	}

	var sb strings.Builder
	sb.WriteString("🎵 **Music Status**\n")

	if status.Playing {
		sb.WriteString("▶️ **Playing**")
		if status.Paused {
			sb.WriteString(" (paused)")
		}
		sb.WriteString("\n")

		if status.CurrentTrack != nil {
			sb.WriteString(FormatTrackInfo(status.CurrentTrack) + "\n")
			sb.WriteString(fmt.Sprintf("📊 Position: %s / %s\n",
				FormatDuration(status.CurrentPositionMs),
				FormatDuration(status.CurrentTrack.DurationMs)))
		}
	} else {
		sb.WriteString("⏹️ **Stopped**\n")
	}

	sb.WriteString(fmt.Sprintf("🔊 Volume: %d%%\n", status.Volume))
	sb.WriteString(fmt.Sprintf("📋 Queue length: %d tracks", status.QueueLength))

	return sb.String()
}

// FormatSearchResults форматирует результаты поиска
func FormatSearchResults(results []*pb.TrackInfo, platform string) string {
	if len(results) == 0 {
		return "No results found"
	}

	var sb strings.Builder
	sb.WriteString(fmt.Sprintf("🔍 **Search results** (from %s):\n", platform))
	for i, track := range results {
		if i >= 10 {
			break
		}
		sb.WriteString(fmt.Sprintf("  %d. %s by %s (%s)\n",
			i+1,
			track.Title,
			track.Artist,
			FormatDuration(track.DurationMs)))
	}
	return sb.String()
}

// LogCommand логирует команду
func LogCommand(cmd *Command) {
	log.Printf("📥 Command: %s from user %s in guild %s", cmd.Type, cmd.UserID, cmd.GuildID)
	if len(cmd.Params) > 0 {
		paramsJSON, _ := json.Marshal(cmd.Params)
		log.Printf("   Params: %s", paramsJSON)
	}
}