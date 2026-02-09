import 'package:flutter/material.dart';
import 'package:act_thumbhash_flutter/act_thumbhash_flutter.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Example ThumbHash (base64 encoded)
    const thumbHash = '1QcSHQRnh493V4dIh4eXh1h4kJUI';
    const imageUrl = 'https://picsum.photos/400/300';

    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('ThumbHash Example')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Basic usage
              SizedBox(
                width: 200,
                height: 150,
                child: Image(
                  image: ThumbHashImageProvider.fromBase64(thumbHash),
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(height: 20),
              // Progressive loading
              SizedBox(
                width: 200,
                height: 150,
                child: FadeInImage(
                  placeholder: ThumbHashImageProvider.fromBase64(thumbHash),
                  image: const NetworkImage(imageUrl),
                  fit: BoxFit.cover,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
