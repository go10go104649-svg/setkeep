import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:interactive_3d/src/form_model.dart';
import 'package:setkeep/bench_press_form.dart';

void main() {
  test(
    'native drawing copy preserves binary animation and authored muscle masks',
    () {
      final source = File('assets/models/bench_press.glb').readAsBytesSync();
      final original = Uint8List.fromList(source);
      final prepared = prepareFormModelForSceneKit(source);
      final sourceLength = ByteData.sublistView(source)
          .getUint32(12, Endian.little);
      final preparedHeader = ByteData.sublistView(prepared);
      final preparedLength = preparedHeader.getUint32(12, Endian.little);
      final document = jsonDecode(
        utf8.decode(prepared.sublist(20, 20 + preparedLength)),
      ) as Map;
      for (final mesh in document['meshes']) {
        for (final primitive in mesh['primitives']) {
          expect(
            (primitive['attributes'] as Map).keys.where(
              (k) => k.toString().startsWith('_MUSCLE_'),
            ),
            isEmpty,
          );
        }
      }
      expect(source, orderedEquals(original));
      expect(
        prepared.sublist(20 + preparedLength),
        orderedEquals(source.sublist(20 + sourceLength)),
      );
      expect(preparedHeader.getUint32(8, Endian.little), prepared.length);
      expect(preparedLength % 4, 0);
      expect(
        () => prepareFormModelForSceneKit(Uint8List(8)),
        throwsFormatException,
      );
    },
  );
  for (final asset in BenchPressFormView.models.values) {
    test(
      '$asset contains a skinned human, equipment and a closed motion loop',
      () {
        final bytes = File(asset).readAsBytesSync();
        final header = ByteData.sublistView(bytes);
        expect(header.getUint32(0, Endian.little), 0x46546c67);
        final jsonLength = header.getUint32(12, Endian.little);
        final gltf = jsonDecode(
          utf8.decode(bytes.sublist(20, 20 + jsonLength)),
        ) as Map<String, dynamic>;
        final binary = ByteData.sublistView(bytes, 28 + jsonLength);
        final nodes = gltf['nodes'] as List;
        final human = nodes.cast<Map>().singleWhere(
          (n) => n['name'] == 'Athlete',
        );
        final primitive = gltf['meshes'][human['mesh']]['primitives'][0] as Map;
        final attributes = primitive['attributes'] as Map;
        expect(
          attributes.keys,
          containsAll([
            'JOINTS_0',
            'WEIGHTS_0',
            'COLOR_0',
            '_MUSCLE_PECTORAL',
            '_MUSCLE_DELTOID_ANTERIOR',
            '_MUSCLE_TRICEPS',
          ]),
        );
        expect(gltf['skins'][human['skin']]['joints'].length, greaterThan(20));
        expect(
          nodes.map((n) => n['name']),
          containsAll(
            asset.contains('incline')
                ? [
                    'Incline backrest',
                    'Incline seat',
                    'Dumbbell_l',
                    'Dumbbell_r',
                  ]
                : ['Bench pad', 'Barbell', 'Bar shaft'],
          ),
        );
        expect(gltf['animations'], hasLength(1));

        List<double> readFloats(int accessorIndex) {
          final accessor = gltf['accessors'][accessorIndex] as Map;
          final view = gltf['bufferViews'][accessor['bufferView']] as Map;
          expect(accessor['componentType'], 5126);
          final width = {'SCALAR': 1, 'VEC3': 3, 'VEC4': 4}[accessor['type']]!;
          final offset =
              (view['byteOffset'] as int? ?? 0) +
              (accessor['byteOffset'] as int? ?? 0);
          final stride = view['byteStride'] as int? ?? width * 4;
          return [
            for (int i = 0; i < accessor['count']; i++)
              for (int c = 0; c < width; c++)
                binary.getFloat32(offset + i * stride + c * 4, Endian.little),
          ];
        }

        for (final name in [
          '_MUSCLE_PECTORAL',
          '_MUSCLE_DELTOID_ANTERIOR',
          '_MUSCLE_TRICEPS',
        ]) {
          final weights = readFloats(attributes[name] as int);
          expect(
            weights.any((w) => w > 0.8),
            isTrue,
            reason: '$name must address an actual surface region',
          );
          expect(weights.every((w) => w.isFinite && w >= 0 && w <= 1), isTrue);
        }
        final animation = gltf['animations'][0] as Map;
        final movingEquipment = <String>{};
        final expectedEquipment = asset.contains('incline')
            ? {'Dumbbell_l', 'Dumbbell_r'}
            : {'Barbell'};
        for (final channel in animation['channels']) {
          final sampler = animation['samplers'][channel['sampler']];
          final times = readFloats(sampler['input']);
          final values = readFloats(sampler['output']);
          expect(times.last - times.first, closeTo(4, 0.001));
          for (int i = 1; i < times.length; i++) {
            expect(times[i], greaterThan(times[i - 1]));
          }
          final width = channel['target']['path'] == 'rotation' ? 4 : 3;
          expect(values.every((v) => v.isFinite), isTrue);
          for (int i = 0; i < width; i++) {
            expect(
              values[i],
              closeTo(values[values.length - width + i], 0.0001),
              reason:
                  'Every animated joint and the bar must close without a jump',
            );
          }
          if (expectedEquipment.contains(
                nodes[channel['target']['node']]['name'],
              ) &&
              channel['target']['path'] == 'translation') {
            final heights = [
              for (int i = 1; i < values.length; i += 3) values[i],
            ];
            final moves =
                heights.reduce((a, b) => a > b ? a : b) -
                    heights.reduce((a, b) => a < b ? a : b) >
                0.3;
            if (moves) {
              movingEquipment.add(
                nodes[channel['target']['node']]['name'] as String,
              );
            }
          }
        }
        expect(movingEquipment, expectedEquipment);
      },
    );
  }

}
