part of '../../main.dart';

class LocalDataRecoveryView extends StatefulWidget {
  const LocalDataRecoveryView({
    required this.failure,
    required this.onRetry,
    required this.loadCloudTarget,
    this.importFileService,
    this.recoveryService,
    super.key,
  });
  final UnreadableLocalFinanceData failure;
  final VoidCallback onRetry;
  final Future<RecoveryCloudTarget> Function() loadCloudTarget;
  final BackupImportFileService? importFileService;
  final LocalDataRecoveryService? recoveryService;

  @override
  State<LocalDataRecoveryView> createState() => _LocalDataRecoveryViewState();
}

class _LocalDataRecoveryViewState extends State<LocalDataRecoveryView> {
  bool _busy = false;
  String? _message;
  LocalDataRecoveryResult? _result;
  late final _recovery =
      widget.recoveryService ??
      LocalDataRecoveryService(failure: widget.failure);

  Future<void> _chooseBackup() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final file = await (widget.importFileService ?? BackupImportFileService())
          .selectBackup();
      if (!mounted || file == null) return;
      final backup = _recovery.validator.validate(file.content);
      final target = await widget.loadCloudTarget();
      if (!mounted) return;
      final confirmed = await _showRestorePreview(
        context,
        backup: backup,
        fileName: file.name,
        cloudEnabled: target.cloudEnabled,
        recoveringUnreadableData: true,
      );
      if (!mounted || confirmed != true) return;
      final result = await _recovery.restore(
        backupJson: file.content,
        target: target,
      );
      if (!mounted) return;
      setState(() => _result = result);
    } on BackupValidationException catch (error) {
      if (mounted) {
        setState(
          () => _message =
              '${error.message} Your saved local data was not changed.',
        );
      }
    } on LocalDataRecoveryException catch (error) {
      if (mounted) setState(() => _message = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _message =
              'Recovery could not finish safely. Your original data has not been reset. Check access to the backup, storage, and your existing sign-in, then try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Icon(
                        _result == null
                            ? AppIcon.error
                            : Icons.check_circle_outline,
                        color: _result == null
                            ? AppTheme.rose
                            : Theme.of(context).colorScheme.primary,
                        size: 40,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _result == null
                            ? '$trackmarkMoneyName could not start'
                            : 'Backup restored',
                        style: Theme.of(context).textTheme.headlineSmall,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _result == null
                            ? 'The saved finance data on this device could not be read. Nothing has been reset or replaced. Cloud sync has not been started.'
                            : 'The validated backup is ready. Your unreadable original and the selected backup were preserved separately.',
                      ),
                      const SizedBox(height: 12),
                      if (_result == null)
                        const Text(
                          'Choose a Trackmark JSON backup from this device or iCloud Drive. Trackmark will validate it and show a restore preview before replacing any data.',
                        ),
                      if (_message != null) ...[
                        const SizedBox(height: 16),
                        Semantics(
                          liveRegion: true,
                          child: Text(
                            _message!,
                            style: TextStyle(color: AppTheme.rose),
                          ),
                        ),
                      ],
                      if (_result != null) ...[
                        const SizedBox(height: 12),
                        SelectableText(
                          'Original preserved at:\n${_result!.originalPath}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                      const SizedBox(height: 24),
                      if (_busy)
                        const Padding(
                          padding: EdgeInsets.all(12),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else if (_result == null)
                        OutlinedButton(
                          onPressed: _chooseBackup,
                          child: const Text('Choose Backup'),
                        )
                      else
                        FilledButton(
                          onPressed: widget.onRetry,
                          child: const Text('Open Trackmark'),
                        ),
                      if (_result == null) ...[
                        TextButton(
                          onPressed: _busy ? null : widget.onRetry,
                          child: const Text('Retry Startup'),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'You can also close Trackmark and return later. Your original data will remain in place.',
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
