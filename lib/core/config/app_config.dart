/// Application configuration constants
class AppConfig {
  AppConfig._();

  // App Info
  static const String appName = 'Local Mind';
  static const String appVersion = '1.0.0';
  static const String appDescription = 'Offline AI Chat Assistant';

  // Model defaults
  static const String defaultModelId = 'qwen2-0.5b';
  static const int defaultContextLength = 2048;
  static const int defaultMaxTokens = 512;
  static const double defaultTemperature = 0.7;

  // Device thresholds
  static const int minRamMB = 3072; // 3GB minimum
  static const int recommendedRamMB = 4096; // 4GB recommended
  static const int lowBatteryThreshold = 20;
  static const int criticalBatteryThreshold = 10;

  // Storage
  static const int maxChatHistoryDays = 365;
  static const int maxThreadsCount = 100;

  // UI
  static const int maxMessageLength = 10000;
  static const int suggestionCount = 3;

  // Default system prompt
  static const String defaultSystemPrompt = '''You are Local Mind, a helpful AI assistant running entirely on the user's device. You are privacy-focused and work offline.

Key traits:
- Helpful and informative
- Concise but thorough
- Honest about limitations
- Privacy-respecting

Since you run locally on limited hardware:
- Keep responses focused and relevant
- Avoid overly long responses unless asked
- Be direct and clear''';

  // Suggested prompts for new users
  static const List<Map<String, String>> defaultSuggestions = [
    {
      'title': 'Explain something',
      'subtitle': 'in simple terms',
      'prompt': 'Can you explain how neural networks work in simple terms?',
    },
    {
      'title': 'Help me write',
      'subtitle': 'an email or message',
      'prompt': 'Help me write a professional email to request time off from work.',
    },
    {
      'title': 'Brainstorm ideas',
      'subtitle': 'for a project',
      'prompt': 'I need creative ideas for a weekend project. What are some fun things I could build or create?',
    },
  ];
}
