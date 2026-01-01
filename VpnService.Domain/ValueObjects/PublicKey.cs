namespace VpnService.Domain.ValueObjects;

public class PublicKey : IEquatable<PublicKey>
{
    public string Value { get; }
    
    public PublicKey(string value)
    {
        if (string.IsNullOrWhiteSpace(value) || value.Length < 10)
            throw new ArgumentException("Invalid public key format");
        Value = value;
    }
    
    public bool Equals(PublicKey? other) => other != null && Value == other.Value;
    public override bool Equals(object? obj) => Equals(obj as PublicKey);
    public override int GetHashCode() => Value.GetHashCode();
    public override string ToString() => Value;
}
