import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'git_command.dart';
import 'git_error.dart';
import 'git_result.dart';

class GitProcessRunner {
  const GitProcessRunner({required this.gitExecutable});

  final String gitExecutable;

  Future<GitResult> run(GitCommand command) async {
    final stopwatch = Stopwatch()..start();
    Process process;
    try {
      process = await Process.start(
        gitExecutable,
        command.arguments,
        workingDirectory: command.workingDirectory,
        environment: <String, String>{
          'GIT_PAGER': 'cat',
          'GIT_EDITOR': 'false',
          'LC_ALL': 'C',
          ...command.environment,
        },
        includeParentEnvironment: true,
        runInShell: false,
      );
    } on ProcessException catch (error) {
      throw GitError(
        kind: GitErrorKind.executableNotFound,
        message: 'The configured Git executable could not be started.',
        technicalDetails: error.message,
      );
    }

    final stdoutFuture = process.stdout.toList();
    final stderrFuture = process.stderr.toList();

    if (command.stdin case final input?) {
      process.stdin.add(input);
    }
    await process.stdin.close();

    int exitCode;
    try {
      exitCode = await process.exitCode.timeout(command.timeout);
    } on TimeoutException {
      process.kill();
      await process.exitCode;
      throw GitError(
        kind: GitErrorKind.timeout,
        message:
            'Git did not finish within ${command.timeout.inSeconds} seconds.',
        technicalDetails: command.description,
      );
    }

    final stdoutBytes = (await stdoutFuture).expand((chunk) => chunk).toList();
    final stderrBytes = (await stderrFuture).expand((chunk) => chunk).toList();
    stopwatch.stop();

    return GitResult(
      exitCode: exitCode,
      stdout: utf8.decode(stdoutBytes, allowMalformed: true),
      stderr: utf8.decode(stderrBytes, allowMalformed: true),
      duration: stopwatch.elapsed,
      sanitizedCommandDescription: command.description,
    );
  }

  Future<GitResult> runChecked(GitCommand command) async {
    final result = await run(command);
    if (!result.isSuccess) throw GitError.fromResult(result);
    return result;
  }
}
