namespace VpnService.Domain.ValueObjects;

public class IpAddress : IEquatable<IpAddress>
{
    public string Value { get; }
    
    public IpAddress(string value)
    {
        if (string.IsNullOrWhiteSpace(value))
            throw new ArgumentException("IP address cannot be empty");
        
        if (!System.Net.IPAddress.TryParse(value, out _))
            throw new ArgumentException($"Invalid IP address format: {value}");
        
        Value = value;
    }
    
    public bool Equals(IpAddress? other) => other != null && Value == other.Value;
    public override bool Equals(object? obj) => Equals(obj as IpAddress);
    public override int GetHashCode() => Value.GetHashCode();
    public override string ToString() => Value;
}
