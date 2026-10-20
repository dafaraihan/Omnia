# MDBList Rating Provider Mark Provenance

> **Automated-validation policy:** Follow the repository-root `AGENTS.md`. Instructions below that call for automated test targets, suites, fixtures, or scripts are historical and superseded; use builds, static checks, and focused manual evidence instead.

Reviewed 2026-08-11. Omnia displays these values from MDBList title responses; it does not imply a direct rating-data integration or endorsement by each named source.

The product owner explicitly accepted community or first-party web artwork for this feature after being informed that several providers restrict trademark use or do not publish a redistribution license. This is a product decision, not a claim that the marks are licensed. Remove an affected asset and restore the adjacent text-only fallback if a rights holder objects.

| Source ID | Display name | Artwork source | Packaged asset | Packaging notes |
| --- | --- | --- | --- | --- |
| `imdb` | IMDb | [Simple Icons 16.21.0](https://cdn.jsdelivr.net/npm/simple-icons@16.21.0/icons/imdb.svg) | `RatingIMDbMark` | Community vector; filled with IMDb brand yellow `#F5C518`. |
| `tmdb` | TMDB | [TMDB official logos](https://www.themoviedb.org/about/logos-attribution) | `RatingTMDBMark` | Official `blue_square_2` vector; geometry and gradient unchanged. |
| `tomatoes` | Rotten Tomatoes | [Rotten Tomatoes licensing page](https://www.rottentomatoes.com/help_desk/licensing) | `RatingRottenTomatoesFreshMark`, `RatingRottenTomatoesRottenMark` | First-party Fresh and Rotten custom-element vectors. The registry selects Rotten below 60. |
| `metacritic` | Metacritic | [Metacritic favicon](https://www.metacritic.com/a/img/favicon.svg) | `RatingMetacriticMark` | First-party color favicon, unchanged. |
| `trakt` | Trakt | [Trakt favicon](https://trakt.tv/favicon.svg) | `RatingTraktMark` | First-party color favicon, unchanged. |
| `letterboxd` | Letterboxd | [Letterboxd brand vector](https://a.ltrbxd.com/logos/letterboxd-decal-dots-pos-rgb.svg) | `RatingLetterboxdMark` | Official RGB dots; the circular background was removed so the mark remains transparent. |
| `popcorn` | Rotten Tomatoes Audience | [Rotten Tomatoes licensing page](https://www.rottentomatoes.com/help_desk/licensing) | `RatingRottenTomatoesAudienceHotMark`, `RatingRottenTomatoesAudienceStaleMark` | First-party Fresh and Rotten audience custom-element vectors. The registry selects stale below 60. |
| `myanimelist` | MyAnimeList | [MyAnimeList mobile mark](https://myanimelist.net/wrap-up/anime-logo-mobile.svg) | `RatingMyAnimeListMark` | First-party vector; white paths changed to brand blue `#2E51A2` for contrast on light and dark surfaces. |
| `rogerebert` | Roger Ebert | [RogerEbert.com wordmark](https://www.rogerebert.com/wp-content/themes/roger-ebert/source/images/roger-ebert-logo.svg) | `RatingRogerEbertMark` | First-party transparent SVG, unchanged. |
| `mdblist` | MDBList | [MDBList mask icon](https://mdblist.com/static/safari-pinned-tab.svg) | `RatingMDBListMark` | First-party vector; filled with the site-declared mask-icon color `#5BBAD5`. |

## Asset integrity

| Asset | Packaged SHA-256 |
| --- | --- |
| `RatingIMDbMark/imdb.svg` | `c3ed7672fa1baabd8e3d1b47add134f723817603cf28f4b77fb22d6ac90ec9ea` |
| `RatingTMDBMark/tmdb-blue-square-2.svg` | `1f9d6d66a2d6ac70b95eb7a2fb83c4e7284eaa881bad21ecda5b7d988cc07bf1` |
| `RatingRottenTomatoesFreshMark/rotten-tomatoes-fresh.svg` | `5af443dc8d8d909ae1afc68a8ed5890ba5c36078d0b37c084d8584f491521f76` |
| `RatingRottenTomatoesRottenMark/rotten-tomatoes-rotten.svg` | `6929d3369f48c9f0a319956e9cf66a172c1d432ff8ab8712261db8b053a53025` |
| `RatingMetacriticMark/metacritic.svg` | `43e3173e06e404ce2aab1876a60f7bca71d7cee99e82ca5fc179cd026d7e58eb` |
| `RatingTraktMark/trakt.svg` | `a8d441896de500a8f080390642744877af8f3965fe68f1d9fe16f9005879282b` |
| `RatingLetterboxdMark/letterboxd.svg` | `bc4fcbf3cd4063f6336b88756f6463b956bcab88147c802405c9611c60f9e2b0` |
| `RatingRottenTomatoesAudienceHotMark/rotten-tomatoes-audience-hot.svg` | `d68e75f299deb8c6ed8578c8b29e283cceaf425c054436ffeaf867181dbbf779` |
| `RatingRottenTomatoesAudienceStaleMark/rotten-tomatoes-audience-stale.svg` | `5f034aa48f4a81c3983b4d8b7e80660a894d78adbd931a7d0760547251f07150` |
| `RatingMyAnimeListMark/myanimelist.svg` | `10969799fe06c9dd7e066c87f78d2c613bca61999fbea68d024ca9124d1759fe` |
| `RatingRogerEbertMark/roger-ebert.svg` | `658eed4515c6e2881a1f20e9ee222fec4ea0e3d9ae08ae1e752816a8e1125910` |
| `RatingMDBListMark/mdblist.svg` | `19446c4f12a30b7bacd36763c46291db3cae3a65cd7a7e9e3e777d037897f94f` |

All rating images render in original color with aspect fit and are decorative for accessibility. Adjacent text and the combined accessibility label provide the provider identity and value. Every future logo addition must update this matrix and `MDBListRatingProviderProvenance`, and must pass the About/provenance tests.
