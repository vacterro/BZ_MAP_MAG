using System.Diagnostics;
using System.Text.Json;
using BZNParser;
using BZNParser.Battlezone;
using BZNParser.Tokenizer;

var hints = BattlezoneBZNHints.BuildHintsBZ2();
foreach (var path in args)
{
    var timer = Stopwatch.StartNew();
    try
    {
        var source = File.ReadAllBytes(path);
        using var stream = new MemoryStream(source);
        using var reader = new BZNStreamReader(stream, path);
        var map = new BZNFileBattlezone(reader, Hints: hints);
        var parseMs = timer.Elapsed.TotalMilliseconds;
        using var output = new MemoryStream();
        using (var writer = new BZNStreamWriter(output, reader.Format, reader.Version, true, reader.GetDefects()))
            map.Write(writer, binary: reader.HasBinary, save: false);
        var bytes = output.ToArray();
        var common = Math.Min(source.Length, bytes.Length);
        var equalPrefix = 0;
        while (equalPrefix < common && source[equalPrefix] == bytes[equalPrefix])
            equalPrefix++;
        Console.WriteLine(JsonSerializer.Serialize(new
        {
            file = Path.GetFileName(path), version = map.Version, parseMs,
            entities = map.Entities.Length,
            paths = map.AiPaths.Select(p => new { name = p.label.Value, type = p.pathType, points = p.points.Length }),
            sourceBytes = source.Length, outputBytes = bytes.Length,
            byteExact = equalPrefix == source.Length && equalPrefix == bytes.Length, equalPrefix
        }));
    }
    catch (Exception ex)
    {
        Console.WriteLine(JsonSerializer.Serialize(new { file = Path.GetFileName(path), error = ex.Message }));
    }
}
