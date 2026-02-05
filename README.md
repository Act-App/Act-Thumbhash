# act-thumbhash
## Introduction
The act-thumbhash libraries implement the
[Thumbhash](https://evanw.github.io/thumbhash/) image placeholder generation
algorithm invented by [Evan Wallace](https://madebyevan.com/) for dart & flutter.

This algorithm is used to calculate a small binary hash representing an image
using a [Discrete Cosine
Transform](https://en.wikipedia.org/wiki/Discrete_cosine_transform). The hash
can then be used to generate a lossy representation of the original image.

The main use case is progressive loading of a web page containing lots of
images, e.g. a photo gallery. Store the hash of each image in your database,
and send it to your client side. On the client side, generate a placeholder image 
from the hash. Then load the original image asynchronously.

## Usage


# Licensing
act-thumbhash is open source software distributed under the
[MIT](https://opensource.org/license/mit) license.
