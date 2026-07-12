import tseslint from '@typescript-eslint/eslint-plugin';
import tsParser from '@typescript-eslint/parser';

export default [
  {ignores: ['.next/**', 'coverage/**', 'node_modules/**']},
  {
    files: ['**/*.{ts,tsx}'],
    languageOptions: {parser: tsParser, parserOptions: {ecmaVersion: 'latest', sourceType: 'module'}},
    plugins: {'@typescript-eslint': tseslint},
    rules: {'@typescript-eslint/no-explicit-any': 'error'}
  }
];
