class AiModelCatalogItem {
  const AiModelCatalogItem({
    required this.id,
    required this.name,
    required this.description,
    required this.fileName,
    required this.url,
    required this.sizeBytes,
    required this.sha256,
  });

  final String id;
  final String name;
  final String description;
  final String fileName;
  final Uri url;
  final int sizeBytes;
  final String sha256;

  String get sizeLabel => '${(sizeBytes / 1024 / 1024).round()} MB';
}

final aiModelCatalog = <AiModelCatalogItem>[
  AiModelCatalogItem(
    id: 'qwen3-0.6b-q2-k',
    name: 'Qwen3 0.6B – Tiny',
    description: 'Nhanh và ít RAM nhất; phù hợp commit diff nhỏ.',
    fileName: 'Qwen3-0.6B-Q2_K.gguf',
    url: Uri.parse(
      'https://huggingface.co/unsloth/Qwen3-0.6B-GGUF/resolve/main/Qwen3-0.6B-Q2_K.gguf?download=true',
    ),
    sizeBytes: 296238784,
    sha256: '26d035ea15c4a2853e8d20ffc56a76f6164e17dbb6c9e532c5766700c404519d',
  ),
  AiModelCatalogItem(
    id: 'qwen3-0.6b-q3-k-m',
    name: 'Qwen3 0.6B – Balanced',
    description: 'Cân bằng tốc độ và chất lượng reasoning.',
    fileName: 'Qwen3-0.6B-Q3_K_M.gguf',
    url: Uri.parse(
      'https://huggingface.co/unsloth/Qwen3-0.6B-GGUF/resolve/main/Qwen3-0.6B-Q3_K_M.gguf?download=true',
    ),
    sizeBytes: 347127488,
    sha256: '30bb9f9222cf58c076277879881a24e7127a10be32076d76d8c70f8defc01f5d',
  ),
  AiModelCatalogItem(
    id: 'qwen3-0.6b-q4-k-m',
    name: 'Qwen3 0.6B – Quality',
    description: 'Chất lượng tốt hơn; khuyến nghị cho máy có từ 8 GB RAM.',
    fileName: 'Qwen3-0.6B-Q4_K_M.gguf',
    url: Uri.parse(
      'https://huggingface.co/unsloth/Qwen3-0.6B-GGUF/resolve/main/Qwen3-0.6B-Q4_K_M.gguf?download=true',
    ),
    sizeBytes: 396705472,
    sha256: 'ac2d97712095a558e31573f62f466a3f9d93990898b0ec79d7c974c1780d524a',
  ),
];
