# Embedding benefit metrics

24 ranking cases, 12 authored intents; 6 safety cases. Repeats are not extra samples.

| Method | NDCG@3 | Supported P@3 | Mean top-one grade (0-2) |
| --- | --- | --- | --- |
| category | 0.4962 | 0.3380 | 0.6574 |
| lexical | 0.8299 | 0.4306 | 1.5000 |
| e5 | 0.9770 | 0.4722 | 1.9583 |
| combined | 0.9770 | 0.4722 | 1.9583 |

## Paired differences

- e5 minus category: +0.4808; cluster interval [0.31696711413690115, 0.6250262425360424]; W/T/L 20/4/0.
- e5 minus lexical: +0.1471; cluster interval [0.04750016919568032, 0.2591208006949857]; W/T/L 7/16/1.
- combined minus category: +0.4808; cluster interval [0.31696711413690115, 0.6250262425360424]; W/T/L 20/4/0.
- combined minus lexical: +0.1471; cluster interval [0.04750016919568032, 0.2591208006949857]; W/T/L 7/16/1.

Methods meeting the predeclared bounded-signal criterion: ['e5', 'combined'].

Authored source relevance is not user satisfaction or production accuracy.
