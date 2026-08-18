// Copyright 2021 MongoDB, Inc.
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';
import 'package:tar/tar.dart';
import 'package:path/path.dart' as path;

class Archive {
// Create an archive of files
  Future<void> archive(Directory sourceDir, File outputFile) async {
    if (!await sourceDir.exists()) {
      throw Exception("Source directory $sourceDir does not exist");
    }

    await findEntries(sourceDir).transform(tarWriter).transform(gzip.encoder).pipe(outputFile.openWrite());
    print("\nArchive ${outputFile.absolute.path} created");
  }

  // Extracts files from an archive
  Future<void> extract(File archive, Directory outputDir) async {
    if (!await outputDir.exists()) {
      await outputDir.create(recursive: true);
    }

    final reader = TarReader(archive.openRead().transform(gzip.decoder));
    while (await reader.moveNext()) {
      final entry = reader.current;
      final header = entry.header;

      var outputPath = path.join(outputDir.absolute.path, entry.name);
      if (!path.isWithin(outputDir.absolute.path, outputPath)) {
        throw Exception("${entry.name} is outside of the archive");
      }

      if (header.typeFlag == TypeFlag.reg) {
        final outputFile = File(outputPath);
        print("extracting ${header.name}");
        await _ensureDirectory(path.dirname(outputPath));
        await outputFile.create(recursive: true);
        await entry.contents.pipe(outputFile.openWrite());
      }
    }

    print("\nArchive ${archive.absolute.path} extracted to ${outputDir.absolute.path}");
  }

  // Creates [dirPath], resolving any dangling symlink along the way to the
  // directory it points at.
  //
  // Consumed from pub.dev this never matters: publishing replaces the package's
  // in-repo symlinks with real directories. Consumed as a git dependency the
  // symlinks survive, and realm/ios/realm_dart.xcframework points into
  // realm_dart/binary/, a gitignored build-output tree that does not exist on a
  // fresh checkout. Creating a file through that dangling link fails with
  // ENOENT, so materialise the target first.
  Future<void> _ensureDirectory(String dirPath) async {
    if (await Directory(dirPath).exists()) return; // follows symlinks

    final parent = path.dirname(dirPath);
    if (parent != dirPath) {
      await _ensureDirectory(parent);
    }

    if (await Link(dirPath).exists()) {
      final target = await Link(dirPath).target();
      await _ensureDirectory(path.normalize(
        path.isAbsolute(target) ? target : path.join(path.dirname(dirPath), target),
      ));
      return;
    }

    await Directory(dirPath).create();
  }

  Stream<TarEntry> findEntries(Directory root) async* {
    await for (final entry in root.list(recursive: true)) {
      var name = path.relative(entry.path, from: root.path);
      if (entry is Directory) {
        continue;
      }

      final stat = await entry.stat();
      print("archiving $name");
      yield TarEntry(
          TarHeader(
              name: name,
              typeFlag: entry is File ? TypeFlag.reg : TypeFlag.dir,
              mode: stat.mode,
              modified: stat.modified,
              accessed: stat.accessed,
              changed: stat.changed,
              size: stat.size),
          // Use entry.openRead() to obtain an input stream for the file that the
          // writer will use later.
          entry is File ? entry.openRead() : Stream.empty());
    }
  }
}
