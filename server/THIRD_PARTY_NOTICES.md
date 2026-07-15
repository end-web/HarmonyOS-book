# Third-Party Runtime

The deployment uses the independently running `changshengyu/reader-dev` service as a Legado-compatible parsing engine.
That project is licensed under GPL-3.0. Its source and license are available at:

- https://github.com/changshengyu/reader-dev

The engine is not linked into the JianHuan API executable. Keep its copyright notices, license, and corresponding
source availability intact when redistributing a deployment image.

The default LibriVox catalog contains public-domain recordings. Individual imported sources remain the operator's
responsibility and must be reviewed for authorization, upstream terms, and content rights before enabling them.

The enabled podcast directory uses Apple's public Search API for discovery and reads audio enclosures from publisher
RSS feeds. Podcast copyrights and availability remain with their respective publishers; this service does not mirror
or redistribute the audio files.
