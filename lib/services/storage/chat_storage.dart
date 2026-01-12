import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';
import 'secure_storage.dart';

/// A chat message
class ChatMessage {
  final String id;
  final String threadId;
  final String role; // 'user' or 'assistant'
  final String content;
  final DateTime timestamp;
  final Map<String, dynamic>? metadata;

  ChatMessage({
    String? id,
    required this.threadId,
    required this.role,
    required this.content,
    DateTime? timestamp,
    this.metadata,
  })  : id = id ?? const Uuid().v4(),
        timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'threadId': threadId,
        'role': role,
        'content': content,
        'timestamp': timestamp.toIso8601String(),
        'metadata': metadata,
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        id: json['id'],
        threadId: json['threadId'],
        role: json['role'],
        content: json['content'],
        timestamp: DateTime.parse(json['timestamp']),
        metadata: json['metadata'],
      );

  bool get isUser => role == 'user';
  bool get isAssistant => role == 'assistant';
}

/// A chat thread/conversation
class ChatThread {
  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? modelId;

  ChatThread({
    String? id,
    required this.title,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.modelId,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'modelId': modelId,
      };

  factory ChatThread.fromJson(Map<String, dynamic> json) => ChatThread(
        id: json['id'],
        title: json['title'],
        createdAt: DateTime.parse(json['createdAt']),
        updatedAt: DateTime.parse(json['updatedAt']),
        modelId: json['modelId'],
      );

  ChatThread copyWith({
    String? title,
    DateTime? updatedAt,
    String? modelId,
  }) {
    return ChatThread(
      id: id,
      title: title ?? this.title,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      modelId: modelId ?? this.modelId,
    );
  }
}

/// Storage service for chat history using Hive
class ChatStorage {
  static const _threadsBoxName = 'chat_threads';
  static const _messagesBoxName = 'chat_messages';

  Box<String>? _threadsBox;
  Box<String>? _messagesBox;
  bool _isInitialized = false;

  /// Initialize storage
  Future<void> initialize() async {
    if (_isInitialized) return;

    await Hive.initFlutter();

    // Get encryption key
    final encryptionKey = await SecureStorage.getEncryptionKey();
    final cipher = HiveAesCipher(utf8.encode(encryptionKey).sublist(0, 32));

    // Open encrypted boxes
    _threadsBox = await Hive.openBox<String>(
      _threadsBoxName,
      encryptionCipher: cipher,
    );

    _messagesBox = await Hive.openBox<String>(
      _messagesBoxName,
      encryptionCipher: cipher,
    );

    _isInitialized = true;
  }

  /// Create a new chat thread
  Future<ChatThread> createThread({String? title, String? modelId}) async {
    final thread = ChatThread(
      title: title ?? 'New Chat',
      modelId: modelId,
    );

    await _threadsBox!.put(thread.id, jsonEncode(thread.toJson()));
    return thread;
  }

  /// Get all threads sorted by updated date
  Future<List<ChatThread>> getAllThreads() async {
    final threads = <ChatThread>[];

    for (final key in _threadsBox!.keys) {
      final json = _threadsBox!.get(key);
      if (json != null) {
        threads.add(ChatThread.fromJson(jsonDecode(json)));
      }
    }

    // Sort by updated date, newest first
    threads.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return threads;
  }

  /// Get a specific thread
  Future<ChatThread?> getThread(String threadId) async {
    final json = _threadsBox!.get(threadId);
    if (json == null) return null;
    return ChatThread.fromJson(jsonDecode(json));
  }

  /// Update a thread
  Future<void> updateThread(ChatThread thread) async {
    await _threadsBox!.put(thread.id, jsonEncode(thread.toJson()));
  }

  /// Delete a thread and its messages
  Future<void> deleteThread(String threadId) async {
    await _threadsBox!.delete(threadId);

    // Delete all messages for this thread
    final keysToDelete = <String>[];
    for (final key in _messagesBox!.keys) {
      final json = _messagesBox!.get(key);
      if (json != null) {
        final message = ChatMessage.fromJson(jsonDecode(json));
        if (message.threadId == threadId) {
          keysToDelete.add(key as String);
        }
      }
    }

    for (final key in keysToDelete) {
      await _messagesBox!.delete(key);
    }
  }

  /// Add a message to a thread
  Future<ChatMessage> addMessage({
    required String threadId,
    required String role,
    required String content,
    Map<String, dynamic>? metadata,
  }) async {
    final message = ChatMessage(
      threadId: threadId,
      role: role,
      content: content,
      metadata: metadata,
    );

    await _messagesBox!.put(message.id, jsonEncode(message.toJson()));

    // Update thread's updatedAt timestamp
    final thread = await getThread(threadId);
    if (thread != null) {
      // Update title from first user message if still default
      String? newTitle;
      if (thread.title == 'New Chat' && role == 'user') {
        newTitle = content.length > 50 ? '${content.substring(0, 47)}...' : content;
      }

      await updateThread(thread.copyWith(
        updatedAt: DateTime.now(),
        title: newTitle,
      ));
    }

    return message;
  }

  /// Get messages for a thread
  Future<List<ChatMessage>> getMessages(String threadId) async {
    final messages = <ChatMessage>[];

    for (final key in _messagesBox!.keys) {
      final json = _messagesBox!.get(key);
      if (json != null) {
        final message = ChatMessage.fromJson(jsonDecode(json));
        if (message.threadId == threadId) {
          messages.add(message);
        }
      }
    }

    // Sort by timestamp
    messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return messages;
  }

  /// Get the last N messages for context
  Future<List<ChatMessage>> getRecentMessages(String threadId, {int limit = 20}) async {
    final messages = await getMessages(threadId);
    if (messages.length <= limit) return messages;
    return messages.sublist(messages.length - limit);
  }

  /// Clear all messages in a thread
  Future<void> clearThread(String threadId) async {
    final keysToDelete = <String>[];

    for (final key in _messagesBox!.keys) {
      final json = _messagesBox!.get(key);
      if (json != null) {
        final message = ChatMessage.fromJson(jsonDecode(json));
        if (message.threadId == threadId) {
          keysToDelete.add(key as String);
        }
      }
    }

    for (final key in keysToDelete) {
      await _messagesBox!.delete(key);
    }
  }

  /// Export thread to JSON
  Future<Map<String, dynamic>> exportThread(String threadId) async {
    final thread = await getThread(threadId);
    final messages = await getMessages(threadId);

    return {
      'thread': thread?.toJson(),
      'messages': messages.map((m) => m.toJson()).toList(),
      'exportedAt': DateTime.now().toIso8601String(),
    };
  }

  /// Import thread from JSON
  Future<ChatThread?> importThread(Map<String, dynamic> data) async {
    if (data['thread'] == null) return null;

    final thread = ChatThread.fromJson(data['thread']);
    await _threadsBox!.put(thread.id, jsonEncode(thread.toJson()));

    final messages = (data['messages'] as List?)
        ?.map((m) => ChatMessage.fromJson(m))
        .toList();

    if (messages != null) {
      for (final message in messages) {
        await _messagesBox!.put(message.id, jsonEncode(message.toJson()));
      }
    }

    return thread;
  }

  /// Get storage size in bytes
  Future<int> getStorageSize() async {
    int size = 0;

    for (final value in _threadsBox!.values) {
      size += value.length;
    }

    for (final value in _messagesBox!.values) {
      size += value.length;
    }

    return size;
  }

  /// Clear all data
  Future<void> clearAll() async {
    await _threadsBox!.clear();
    await _messagesBox!.clear();
  }

  /// Close storage
  Future<void> close() async {
    await _threadsBox?.close();
    await _messagesBox?.close();
  }
}
